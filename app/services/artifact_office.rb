require "zip"
require "base64"

module ArtifactOffice
  REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships".freeze
  PACKAGE_REL = "http://schemas.openxmlformats.org/package/2006/relationships".freeze
  XML_HEADER = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'.freeze

  def self.generate(version, format)
    unless ArtifactTypes::FORMATS.fetch(version.kind, []).include?(format) && format != "pdf"
      raise ArgumentError, "Unsupported Office format for #{version.kind}"
    end
    source = ArtifactTypes.validate!(version.kind, version.content).first
    { "docx" => Doc, "xlsx" => Sheet, "pptx" => Slides }.fetch(format).new(source, version).generate
  end

  class Package
    def initialize(source, version)
      @source = source
      @tokens = DesignKit::DEFAULT_TOKENS.merge(version.design_tokens)
      @parts = {}
      @types = {}
    end

    private

    def xml(value)
      ERB::Util.html_escape(value.to_s.gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/, ""))
    end

    def part(path, body, content_type = nil)
      @parts[path] = XML_HEADER + body
      @types[path] = content_type if content_type
    end

    def relationships(path, entries)
      part(path, %(<Relationships xmlns="#{PACKAGE_REL}">#{entries.map { |id, type, target| %(<Relationship Id="#{xml(id)}" Type="#{REL}/#{type}" Target="#{xml(target)}"/>) }.join}</Relationships>))
    end

    def package(main)
      relationships("_rels/.rels", [ [ "rId1", "officeDocument", main ] ])
      defaults = { "rels" => "application/vnd.openxmlformats-package.relationships+xml", "xml" => "application/xml", "png" => "image/png", "jpeg" => "image/jpeg" }
      part("[Content_Types].xml", %(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">#{defaults.map { |extension, type| %(<Default Extension="#{extension}" ContentType="#{type}"/>) }.join}#{@types.map { |path, type| %(<Override PartName="/#{path}" ContentType="#{type}"/>) }.join}</Types>))
      Zip::OutputStream.write_buffer do |zip|
        @parts.each do |path, bytes|
          zip.put_next_entry(path)
          zip.write(bytes)
        end
      end.string
    end

    def color(name)
      @tokens.fetch(name).delete_prefix("#")
    end

    def font
      { "serif" => "Georgia", "monospace" => "Courier New" }.fetch(@tokens["font"], "Arial")
    end

    def formatted(value, format)
      return value.to_s if value.nil? || format.nil? || format == "text"
      helper = ActiveSupport::NumberHelper
      case format
      when "int" then helper.number_to_rounded(value, precision: 0, delimiter: ".", separator: ",")
      when "idr" then "Rp #{helper.number_to_rounded(value, precision: 0, delimiter: '.', separator: ',')}"
      when "pct" then value.is_a?(Numeric) ? "#{helper.number_to_rounded(value * 100, precision: 2, strip_insignificant_zeros: true, separator: ',')}%" : value.to_s
      when "date" then Date.iso8601(value.to_s).strftime("%d/%m/%Y")
      else value.to_s
      end
    rescue Date::Error, ArgumentError
      value.to_s
    end
  end
end
