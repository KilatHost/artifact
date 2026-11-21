module ArtifactOffice
  class Sheet < Package
    NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main".freeze
    FORMATS = { "int" => "#,##0", "idr" => '"Rp "#,##0', "pct" => "0.##%", "date" => "dd/mm/yyyy", "text" => "@" }.freeze

    def generate
      sheets = @source["tabs"].each_with_index.map do |tab, index|
        worksheet(tab, index + 1)
        %(<sheet name="#{xml(tab['name'])}" sheetId="#{index + 1}" r:id="sheet#{index + 1}"/>)
      end.join
      part("xl/workbook.xml", %(<workbook xmlns="#{NS}" xmlns:r="#{REL}"><sheets>#{sheets}</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml")
      relations = @source["tabs"].each_index.map { |i| [ "sheet#{i + 1}", "worksheet", "worksheets/sheet#{i + 1}.xml" ] }
      relationships("xl/_rels/workbook.xml.rels", relations + [ [ "styles", "styles", "styles.xml" ] ])
      styles
      package("xl/workbook.xml")
    end

    private

    def styles
      formats = FORMATS.values.each_with_index.map { |format, i| %(<numFmt numFmtId="#{164 + i}" formatCode="#{xml(format)}"/>) }.join
      xfs = '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      xfs += FORMATS.values.each_index.map { |i| %(<xf numFmtId="#{164 + i}" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>) }.join
      xfs += '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>'
      part("xl/styles.xml", %(<styleSheet xmlns="#{NS}"><numFmts count="5">#{formats}</numFmts><fonts count="2"><font><sz val="11"/><name val="#{font}"/></font><font><b/><sz val="11"/><name val="#{font}"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7">#{xfs}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>), "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml")
    end

    def style(format)
      index = FORMATS.keys.index(format)
      index ? index + 1 : 0
    end

    def worksheet(tab, index)
      evaluator = ArtifactSheetFormulas.new(tab)
      columns = tab["columns"]
      rows = [ %(<row r="1">#{columns.each_with_index.map { |col, c| cell(col['title'], "#{(65 + c).chr}1", 6) }.join}</row>) ]
      tab["rows"].each_with_index do |row, r|
        cells = columns.each_with_index.map do |col, c|
          source = row[c]
          value = evaluator.cell(r + 1, c)
          formula = source["f"].delete_prefix("=") if source.is_a?(Hash) && evaluator.valid_syntax?(source["f"])
          cell(value, "#{(65 + c).chr}#{r + 2}", style(col["format"]), formula: formula, date: col["format"] == "date")
        end.join
        rows << %(<row r="#{r + 2}">#{cells}</row>)
      end
      cols = columns.each_with_index.map { |col, c| %(<col min="#{c + 1}" max="#{c + 1}" width="22" customWidth="1" style="#{style(col['format'])}"/>) }.join
      part("xl/worksheets/sheet#{index}.xml", %(<worksheet xmlns="#{NS}"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>#{cols}</cols><sheetData>#{rows.join}</sheetData></worksheet>), "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml")
    end

    def cell(value, address, style, formula: nil, date: false)
      if date && value.is_a?(String) && !formula
        begin
          value = (Date.iso8601(value) - Date.new(1899, 12, 30)).to_i
        rescue Date::Error
          # Keep non-date text as text.
        end
      end
      type, body = case value
      when true, false then [ "b", "<v>#{value ? 1 : 0}</v>" ]
      when Numeric then [ "n", "<v>#{value}</v>" ]
      when nil then [ "n", "" ]
      else
        if value == ArtifactSheetFormulas::ERROR
          [ "e", "<v>#VALUE!</v>" ]
        elsif formula
          [ "str", "<v>#{xml(value)}</v>" ]
        else
          [ "inlineStr", "<is><t xml:space=\"preserve\">#{xml(value)}</t></is>" ]
        end
      end
      %(<c r="#{address}" s="#{style}" t="#{type}">#{formula ? "<f>#{xml(formula)}</f>" : ''}#{body}</c>)
    end
  end
end
