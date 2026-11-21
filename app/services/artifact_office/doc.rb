module ArtifactOffice
  class Doc < Package
    W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main".freeze

    def generate
      content = logo + @source["blocks"].map { |block| block_xml(block) }.join
      part("word/document.xml", %(<w:document xmlns:w="#{W}" xmlns:r="#{REL}"><w:body>#{content}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="850" w:right="850" w:bottom="850" w:left="850"/></w:sectPr></w:body></w:document>), "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml")
      part("word/styles.xml", %(<w:styles xmlns:w="#{W}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="#{font}" w:hAnsi="#{font}"/><w:color w:val="#{color('foreground')}"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>), "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml")
      relations = [ [ "styles", "styles", "styles.xml" ] ]
      relations << [ "logo", "image", "media/logo.#{logo_extension}" ] if @source["logo"]
      relationships("word/_rels/document.xml.rels", relations)
      package("word/document.xml")
    end

    private

    def paragraph(text, heading: nil, bold: false)
      properties = heading ? %(<w:pPr><w:keepNext/><w:outlineLvl w:val="#{heading - 1}"/></w:pPr>) : ""
      run_properties = heading ? %(<w:b/><w:color w:val="#{color('accent')}"/><w:sz w:val="#{40 - heading * 4}"/>) : (bold ? "<w:b/>" : "")
      runs = text.to_s.split("\n", -1).map { |line| %(<w:r><w:rPr>#{run_properties}</w:rPr><w:t xml:space="preserve">#{xml(line)}</w:t></w:r>) }.join("<w:r><w:br/></w:r>")
      "<w:p>#{properties}#{runs}</w:p>"
    end

    def table(head, rows, formats = [])
      width = head.empty? ? rows.map(&:length).max.to_i : head.length
      grid = "<w:tblGrid>#{Array.new(width, '<w:gridCol w:w="2400"/>').join}</w:tblGrid>"
      table_rows = []
      table_rows << [ head, true ] unless head.empty?
      table_rows += rows.map { |row| [ row, false ] }
      body = table_rows.map do |row, header|
        cells = width.times.map { |i| "<w:tc><w:tcPr><w:tcW w:w=\"2400\" w:type=\"dxa\"/></w:tcPr>#{paragraph(header ? row[i] : formatted(row[i], formats[i]), bold: header)}</w:tc>" }.join
        "<w:tr>#{header ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}#{cells}</w:tr>"
      end.join
      borders = %w[top left bottom right insideH insideV].map { |edge| %(<w:#{edge} w:val="single" w:sz="4" w:color="CCCCCC"/>) }.join
      "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>#{borders}</w:tblBorders></w:tblPr>#{grid}#{body}</w:tbl>"
    end

    def block_xml(block)
      case block["t"]
      when "heading" then paragraph(block["text"], heading: block.fetch("level", 1))
      when "paragraph" then paragraph(block["text"])
      when "fields" then table([], block["rows"])
      when "table" then table(block["head"], block["rows"], block.fetch("format", []))
      when "totals" then table([], block["rows"], [ nil, block["format"] ])
      when "list" then block["items"].each_with_index.map { |item, i| paragraph("#{block['ordered'] ? "#{i + 1}." : '•'} #{item}") }.join
      when "signature" then paragraph(block["place_date"]) + paragraph("") + paragraph(block["name"], bold: true) + paragraph(block["role"])
      when "pagebreak" then '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
      end
    end

    def logo_extension
      @source["logo"].start_with?("data:image/png;") ? "png" : "jpeg"
    end

    def logo
      return "" unless @source["logo"]
      @parts["word/media/logo.#{logo_extension}"] = Base64.decode64(@source["logo"].split(",", 2).last)
      %(<w:p><w:r><w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><wp:extent cx="1828800" cy="914400"/><wp:docPr id="1" name="Logo"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="0" name="Logo"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="logo"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1828800" cy="914400"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>)
    end
  end
end
