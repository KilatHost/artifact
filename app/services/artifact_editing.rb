class ArtifactEditing
  EDITABLE_KINDS = %w[document markdown html].freeze
  HTML_TEXT_ELEMENTS = %w[h1 h2 h3 h4 h5 h6 p figcaption caption span div th td].freeze

  def self.editable?(version)
    EDITABLE_KINDS.include?(version.kind)
  end

  def self.markdown_fields(content)
    content = content.gsub(/\r\n?/, "\n")
    lines = content.lines(chomp: true)
    fields = []
    Commonmarker.parse(content, options: ArtifactRendering::MARKDOWN_OPTIONS).walk do |node|
      next unless %i[heading paragraph].include?(node.type)
      text = node.first_child
      next unless text&.type == :text && !text.next_sibling

      position = node.source_position
      next unless position[:start_line] == position[:end_line]

      index = position[:start_line] - 1
      line = lines[index]
      prefix, label, style = case node.type
      when :heading
        [ line[/\A\#{1,6}[ \t]+/], "Heading", "heading-#{node.header_level}" ]
      when :paragraph
        if node.parent.type == :item
          [ line[/\A(?:[-+*]|\d{1,9}[.)])[ \t]+/], "List item", "list-item" ]
        elsif node.parent.type == :document
          [ "", "Paragraph", "paragraph" ]
        end
      end
      next unless prefix && line == prefix + text.string_content

      fields << { index: index, prefix: prefix, label: label, style: style, text: text.string_content }
    end
    fields
  end

  def self.html_fields(content)
    html_nodes(parse_html(content)).transform_values(&:text)
  end

  def self.revise_html(content, edits)
    tree = parse_html(content)
    changed = false
    html_nodes(tree).each do |name, node|
      value = edits[name]
      next unless value.is_a?(String) && value != node.text

      node.content = value
      changed = true
    end
    changed ? tree.to_html : content
  end

  def self.parse_html(content)
    ArtifactRendering.full_document?(content) ? Nokogiri::HTML5.parse(content) : Nokogiri::HTML5.fragment(content)
  end

  def self.html_nodes(tree)
    tree.css("[data-kilat-editable]").group_by { |node| node["data-kilat-editable"] }.filter_map do |name, nodes|
      node = nodes.first
      if nodes.one? && name.match?(/\A[a-zA-Z][a-zA-Z0-9_-]{0,63}\z/) &&
          !node.namespace && HTML_TEXT_ELEMENTS.include?(node.name) && node.children.all?(&:text?)
        [ name, node ]
      end
    end.to_h
  end

  private_class_method :parse_html, :html_nodes
end
