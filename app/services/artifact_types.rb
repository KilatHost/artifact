require "base64"
require "json"

# Portable typed sources, checked against config/artifact_types and cross-field rules.
module ArtifactTypes
  class Invalid < StandardError; end

  KINDS = %w[doc sheet slides].freeze
  LABELS = { "doc" => "Doc", "sheet" => "Sheet", "slides" => "Slides" }.freeze
  # The download formats per kind, the first one the primary.
  FORMATS = { "doc" => %w[docx pdf], "sheet" => %w[xlsx pdf], "slides" => %w[pptx pdf] }.freeze
  CONTENT_TYPES = {
    "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "pdf" => "application/pdf"
  }.freeze
  MAX_SOURCE_BYTES = 1.megabyte
  MAX_LOGO_BYTES = 200.kilobytes
  # Founder decision 2026-11-16 (§9): a fixed list; anything else is refused by name at publish.
  FORMULAS = %w[SUM AVERAGE IF ROUND MIN MAX COUNT VLOOKUP].freeze
  FUNCTION_CALL = /([A-Za-z_][A-Za-z0-9_.]*)\s*\(/
  STRING_LITERAL = /"(?:[^"]|"")*"/

  module_function

  def schema(kind)
    @schemas ||= KINDS.index_with { |name| JSON.parse(File.read(Rails.root.join("config", "artifact_types", "#{name}.json"))).freeze }.freeze
    @schemas.fetch(kind)
  end

  def label(kind) = LABELS[kind]
  def primary_format(kind) = FORMATS.fetch(kind).first

  # The source as a plain JSON value (string keys) and its canonical bytes, or Invalid naming the field.
  def validate!(kind, source)
    raise Invalid, "kind must be one of: html, #{KINDS.join(', ')}." unless KINDS.include?(kind)
    value = normalize(source)
    raise Invalid, "source must be a JSON object, for example {\"kind\":\"#{kind}\", ...}." unless value.is_a?(Hash)
    raise Invalid, "source.kind must be \"#{kind}\", the same as kind." unless value["kind"] == kind
    root = schema(kind)
    Validator.new(root).check!(value, root, "source")
    send("check_#{kind}!", value)
    json = JSON.generate(value)
    if json.bytesize > MAX_SOURCE_BYTES
      raise Invalid, "The source is #{ActiveSupport::NumberHelper.number_to_human_size(json.bytesize)}; a #{label(kind)} source is at most #{ActiveSupport::NumberHelper.number_to_human_size(MAX_SOURCE_BYTES)}."
    end
    [ value, json ]
  end

  def normalize(source)
    if source.is_a?(String)
      raise Invalid, "source is over #{ActiveSupport::NumberHelper.number_to_human_size(MAX_SOURCE_BYTES)}." if source.bytesize > MAX_SOURCE_BYTES
      begin
        return JSON.parse(source)
      rescue JSON::ParserError
        raise Invalid, "source must be a JSON object; the text sent isn't valid JSON."
      end
    end
    JSON.parse(JSON.generate(source))
  rescue JSON::GeneratorError, JSON::NestingError
    raise Invalid, "source must be a JSON object."
  end

  def check_doc!(source)
    if (logo = source["logo"])
      bytes = Base64.decode64(logo.split(",", 2).last.to_s).bytesize
      raise Invalid, "source.logo is #{ActiveSupport::NumberHelper.number_to_human_size(bytes)}; the logo is at most #{ActiveSupport::NumberHelper.number_to_human_size(MAX_LOGO_BYTES)}." if bytes > MAX_LOGO_BYTES
    end
    source["blocks"].each_with_index do |block, index|
      next unless block["t"] == "table"
      width = block["head"].length
      if block["format"] && block["format"].length > width
        raise Invalid, "source.blocks[#{index}].format has #{block['format'].length} entries; the table has #{width} columns."
      end
      rows_fit!(block["rows"], width, "source.blocks[#{index}]", "table")
    end
  end

  def check_sheet!(source)
    seen = {}
    source["tabs"].each_with_index do |tab, index|
      path = "source.tabs[#{index}]"
      key = tab["name"].strip.downcase
      raise Invalid, "#{path}.name \"#{tab['name']}\" is used by another tab; tab names must differ." if seen[key]
      seen[key] = true
      rows_fit!(tab["rows"], tab["columns"].length, path, "tab")
      tab["rows"].each_with_index do |row, row_index|
        row.each_with_index do |cell, column|
          formula!(cell["f"], "#{path}.rows[#{row_index}][#{column}]") if cell.is_a?(Hash)
        end
      end
    end
  end

  def check_slides!(source)
    source["slides"].each_with_index do |slide, index|
      rows_fit!(slide["rows"], slide["head"].length, "source.slides[#{index}]", "table") if slide["layout"] == "table"
    end
  end

  def rows_fit!(rows, width, path, noun)
    rows.each_with_index do |row, index|
      next if row.length <= width
      raise Invalid, "#{path}.rows[#{index}] has #{row.length} cells; the #{noun} has #{width} columns."
    end
  end

  # A cheap check of the function names.
  def formula!(formula, path)
    names = formula.gsub(STRING_LITERAL, '""').scan(FUNCTION_CALL).flatten.map(&:upcase).uniq
    unsupported = names - FORMULAS
    return if unsupported.empty?
    raise Invalid, "#{path} uses #{unsupported.first}, which Kilat sheets don't support. Use only #{FORMULAS.join(', ')} and + - * /."
  end

  # The subset of JSON Schema (2020-12) the three files use: $ref (local), oneOf (told apart by a const field such as
  # "t" or "layout"), type, const, enum, required, properties, additionalProperties false, items, prefixItems,
  # minItems/maxItems, minLength/maxLength, minimum/maximum and pattern.
  class Validator
    TYPE_NAMES = { "string" => "text", "number" => "a number", "integer" => "a whole number", "boolean" => "true or false",
      "null" => "null", "array" => "a list", "object" => "an object" }.freeze

    def initialize(root)
      @root = root
    end

    def check!(value, schema, path)
      schema = resolve(schema)
      return one_of!(value, schema["oneOf"], path) if schema["oneOf"]
      type!(value, schema["type"], path) if schema["type"]
      raise Invalid, "#{path} must be #{show(schema['const'])}." if schema.key?("const") && value != schema["const"]
      if schema["enum"] && !schema["enum"].include?(value)
        raise Invalid, "#{path} must be one of: #{schema['enum'].map { |option| show(option) }.join(', ')}."
      end
      case value
      when Hash then object!(value, schema, path)
      when Array then array!(value, schema, path)
      when String then string!(value, schema, path)
      when Numeric then number!(value, schema, path)
      end
    end

    private
      def resolve(schema)
        while schema.is_a?(Hash) && schema["$ref"]
          ref = schema["$ref"]
          raise ArgumentError, "Only local $defs refs are supported: #{ref}" unless ref.start_with?("#/$defs/")
          schema = @root.fetch("$defs").fetch(ref.delete_prefix("#/$defs/"))
        end
        schema
      end

      def one_of!(value, options, path)
        options = options.map { |option| resolve(option) }
        key = options.first.fetch("properties").keys.find { |name| options.all? { |option| option.dig("properties", name)&.key?("const") } }
        raise ArgumentError, "oneOf at #{path} has no const field to tell the options apart" unless key
        names = options.map { |option| option.dig("properties", key, "const") }
        raise Invalid, "#{path} must be an object with \"#{key}\" (one of: #{names.join(', ')})." unless value.is_a?(Hash)
        raise Invalid, "#{path}.#{key} is required (one of: #{names.join(', ')})." unless value.key?(key)
        index = names.index(value[key])
        raise Invalid, "#{path}.#{key} must be one of: #{names.join(', ')}." unless index
        check!(value, options[index], path)
      end

      def type!(value, types, path)
        types = Array(types)
        return if types.any? { |type| type?(value, type) }
        raise Invalid, "#{path} must be #{types.map { |type| TYPE_NAMES.fetch(type) }.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}."
      end

      def type?(value, type)
        case type
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "number" then value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
        when "boolean" then value == true || value == false
        when "null" then value.nil?
        when "array" then value.is_a?(Array)
        when "object" then value.is_a?(Hash)
        end
      end

      def object!(value, schema, path)
        Array(schema["required"]).each do |key|
          raise Invalid, "#{path}.#{key} is required." unless value.key?(key)
        end
        properties = schema["properties"] || {}
        value.each do |key, item|
          if properties.key?(key)
            check!(item, properties[key], "#{path}.#{key}")
          elsif schema["additionalProperties"] == false
            raise Invalid, "#{path}.#{key} isn't allowed here (allowed: #{properties.keys.join(', ')})."
          end
        end
      end

      def array!(value, schema, path)
        if schema["minItems"] && value.length < schema["minItems"]
          raise Invalid, "#{path} needs at least #{schema['minItems']} #{schema['minItems'] == 1 ? 'item' : 'items'}."
        end
        if schema["maxItems"] && value.length > schema["maxItems"]
          raise Invalid, "#{path} has #{value.length} items; the limit is #{schema['maxItems']}."
        end
        prefix = schema["prefixItems"] || []
        value.each_with_index do |item, index|
          item_schema = prefix[index] || schema["items"]
          check!(item, item_schema, "#{path}[#{index}]") if item_schema
        end
      end

      def string!(value, schema, path)
        raise Invalid, "#{path} must be valid UTF-8 text." unless value.valid_encoding?
        if schema["minLength"] && value.length < schema["minLength"]
          raise Invalid, schema["minLength"] == 1 ? "#{path} can't be empty." : "#{path} must be at least #{schema['minLength']} characters."
        end
        if schema["maxLength"] && value.length > schema["maxLength"]
          raise Invalid, "#{path} is #{value.length} characters; the limit is #{schema['maxLength']}."
        end
        raise Invalid, "#{path} isn't in the expected form." if schema["pattern"] && !pattern(schema["pattern"]).match?(value)
      end

      def number!(value, schema, path)
        raise Invalid, "#{path} must be at least #{schema['minimum']}." if schema["minimum"] && value < schema["minimum"]
        raise Invalid, "#{path} must be at most #{schema['maximum']}." if schema["maximum"] && value > schema["maximum"]
      end

      # ECMA ^ and $ anchor the whole string; Ruby's anchor lines.
      def pattern(source)
        (@patterns ||= {})[source] ||= Regexp.new(source.sub(/\A\^/, '\A').sub(/(?<!\\)\$\z/, '\z'))
      end

      def show(value)
        value.nil? ? "null" : value.to_json
      end
  end
end
