class ArtifactTypedHtml
  def self.body(version)
    new(ArtifactTypes.validate!(version.kind, version.content).first).body
  end

  def self.css(kind)
    common = ".typed p{white-space:pre-wrap}.typed h1,.typed h2,.typed h3{color:var(--accent)}.pagebreak{break-before:page}.signature{margin-top:3em}.logo{max-height:100px}.columns{display:grid;grid-template-columns:1fr 1fr;gap:2em}"
    case kind
    when "doc"
      common + "main.typed{max-width:180mm;min-height:267mm}@page{size:A4}"
    when "slides"
      common + "main.typed{max-width:none;padding:0}.slide{box-sizing:border-box;aspect-ratio:16/9;padding:5%;margin:20px auto;max-width:1200px;border:1px solid #ddd;overflow:hidden}.big-number{font-size:5em}@page{size:320mm 180mm;margin:0}@media print{.slide{width:320mm;height:180mm;max-width:none;margin:0;border:0;break-after:page}.slide:last-child{break-after:auto}}"
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
      @source["slides"].map { |slide| "<section class=\"slide\">#{slide_html(slide)}</section>" }.join
    end
    "<main class=\"typed\">#{content}</main>"
  end

  private

  def escape(value)
    ERB::Util.html_escape(value.to_s)
  end

  def format_value(value, format)
    return escape(value) if value.nil? || value == ArtifactSheetFormulas::ERROR
    number = ActiveSupport::NumberHelper
    rendered = case format
    when "int" then number.number_to_rounded(value, precision: 0, delimiter: ".", separator: ",")
    when "idr" then "Rp #{number.number_to_rounded(value, precision: 0, delimiter: '.', separator: ',')}"
    when "pct" then value.is_a?(Numeric) ? "#{number.number_to_rounded(value * 100, precision: 2, strip_insignificant_zeros: true, separator: ',')}%" : value
    when "date" then Date.iso8601(value.to_s).strftime("%d/%m/%Y")
    else value
    end
    escape(rendered)
  rescue Date::Error, ArgumentError
    escape(value)
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
