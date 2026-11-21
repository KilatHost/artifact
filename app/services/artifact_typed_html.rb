class ArtifactTypedHtml
  def self.body(version)
    new(ArtifactTypes.validate!(version.kind, version.content).first).body
  end

  def self.css(kind)
    common = ".typed p{white-space:pre-wrap}.typed h1,.typed h2,.typed h3{color:var(--accent)}.pagebreak{break-before:page}.signature{margin-top:3em}.logo{max-height:100px}.columns{display:grid;grid-template-columns:1fr 1fr;gap:2em}"
    case kind
    when "doc"
      common + "main.typed{max-width:180mm;min-height:267mm}@page{size:A4}@media print{main.typed{min-height:0}}"
    when "slides"
      common + "main.typed{max-width:none;padding:0}.slide{box-sizing:border-box;aspect-ratio:16/9;padding:5%;margin:20px auto;max-width:1200px;border:1px solid #ddd;overflow:hidden}.slide-table{padding:30px}.slide-table h1{font-size:24px;line-height:1.2;margin:0 0 16px}.slide-table table{table-layout:fixed;font-size:var(--table-font-size);line-height:1.15}.slide-table td,.slide-table th{padding:3px;overflow-wrap:anywhere;word-break:break-word;white-space:pre-wrap}.big-number{font-size:5em}@page{size:320mm 180mm;margin:0}@media print{.slide{width:320mm;height:180mm;max-width:none;margin:0;border:0;break-after:page}.slide:last-child{break-after:auto}}"
    else common + ".tab{margin-bottom:3em}thead{display:table-header-group}"
    end
  end

  def initialize(source)
    @source = source
  end

  def body
    content = case @source["kind"]
    when "doc"
      logo = @source["logo"] ? "<img class=\"logo\" alt=\"Logo\" src=\"#{escape(@source['logo'])}\">" : ""
      logo + @source["blocks"].map { |block| block_html(block) }.join
    when "sheet"
      @source["tabs"].map do |tab|
        formulas = ArtifactSheetFormulas.new(tab)
        rows = tab["rows"].each_index.map { |r| tab["columns"].each_index.map { |c| formulas.cell(r + 1, c) } }
        "<section class=\"tab\"><h2>#{escape(tab['name'])}</h2>#{table(tab['columns'].pluck('title'), rows, tab['columns'].pluck('format'))}</section>"
      end.join
    when "slides"
      @source["slides"].map do |slide|
        attributes = slide["layout"] == "table" ? "slide slide-table\" style=\"--table-font-size:#{slide_table_font_size(slide)}px" : "slide"
        "<section class=\"#{attributes}\">#{slide_html(slide)}</section>"
      end.join
    end
    "<main class=\"typed\">#{content}</main>"
  end

  private

  def slide_table_font_size(slide)
    rows = [ slide["head"] ] + slide["rows"]
    cell_width = 1120.0 / slide["head"].length - 8
    (6..24).to_a.reverse_each do |half_points|
      size = half_points / 2.0
      characters = [ (cell_width / size).floor, 1 ].max
      lines = rows.sum do |row|
        row.map { |value| value.to_s.split("\n", -1).sum { |line| [ (line.length.to_f / characters).ceil, 1 ].max } }.max || 1
      end
      return size if lines * size * 1.15 + rows.length * 7 <= 500
    end
    3
  end

  def escape(value)
    ERB::Util.html_escape(value.to_s)
  end

  def format_value(value, format)
    return escape(value) if value == ArtifactSheetFormulas::ERROR
    escape(ArtifactValueFormatting.format(value, format))
  end

  def table(head, rows, formats = [])
    header = head.empty? ? "" : "<thead><tr>#{head.map { |v| "<th>#{escape(v)}</th>" }.join}</tr></thead>"
    width = head.empty? ? rows.map(&:length).max.to_i : head.length
    body = rows.map { |row| "<tr>#{width.times.map { |c| "<td>#{format_value(row[c], formats[c])}</td>" }.join}</tr>" }.join
    "<table>#{header}<tbody>#{body}</tbody></table>"
  end

  def list(items, ordered = false)
    tag = ordered ? "ol" : "ul"
    "<#{tag}>#{items.map { |item| "<li>#{escape(item)}</li>" }.join}</#{tag}>"
  end

  def block_html(block)
    case block["t"]
    when "heading" then "<h#{block.fetch('level', 1)}>#{escape(block['text'])}</h#{block.fetch('level', 1)}>"
    when "paragraph" then "<p>#{escape(block['text'])}</p>"
    when "fields" then table([], block["rows"])
    when "table" then table(block["head"], block["rows"], block.fetch("format", []))
    when "totals" then table([], block["rows"], [ nil, block["format"] ])
    when "list" then list(block["items"], block["ordered"])
    when "signature" then "<div class=\"signature\"><p>#{escape(block['place_date'])}</p><p>#{escape(block['name'])}<br>#{escape(block['role'])}</p></div>"
    when "pagebreak" then '<div class="pagebreak"></div>'
    end
  end

  def slide_html(slide)
    title = slide["title"] ? "<h1>#{escape(slide['title'])}</h1>" : ""
    title + case slide["layout"]
    when "title" then "<p>#{escape(slide['subtitle'])}</p>"
    when "closing" then "<p>#{escape(slide['text'])}</p>"
    when "big-number" then "<div class=\"big-number\">#{escape(slide['number'])}</div><p>#{escape(slide['caption'])}</p>"
    when "bullets" then list(slide["bullets"])
    when "two-column" then "<div class=\"columns\"><div>#{list(slide['left'])}</div><div>#{list(slide['right'])}</div></div>"
    when "table" then table(slide["head"], slide["rows"])
    end
  end
end
