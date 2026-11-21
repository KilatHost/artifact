require "test_helper"
require_relative "../test_helpers/artifact_office_examples"

class ArtifactOfficeTest < ActiveSupport::TestCase
  include ArtifactOfficeExamples

  def generate(source, format)
    version = ArtifactVersion.new(kind: source["kind"], content: source.to_json, design_tokens: DesignKit::DEFAULT_TOKENS)
    bytes = ArtifactOffice.generate(version, format)
    Zip::File.open_buffer(bytes) do |zip|
      zip.each do |entry|
        refute_predicate entry, :zip64?, "#{format}: #{entry.name} should use standard ZIP headers"
        next unless entry.name.end_with?(".xml", ".rels")
        assert Nokogiri::XML(entry.get_input_stream.read) { |config| config.strict }, entry.name
      end
      yield zip
    end
  end

  def xml_part(zip, path)
    Nokogiri::XML(zip.read(path)).remove_namespaces!
  end

  test "docx contains all blocks formats image relationships and A4 page breaks" do
    generate(office_doc, "docx") do |zip|
      document = xml_part(zip, "word/document.xml")
      assert_equal 4, document.xpath("//tbl").length
      %w[Rp\ 750.000 1.234 25% 16/11/2026 A&B 1.\ First\ item •\ A\ bullet Budi\ Santoso].each { |text| assert_includes document.text, text }
      assert_includes document.text, "<script>Not markup & still text</script>"
      assert_equal "page", document.at_xpath("//br[@type='page']")["type"]
      assert_equal "11906", document.at_xpath("//pgSz")["w"]
      assert_equal "logo", document.at_xpath("//blip")["embed"]
      assert zip.read("word/media/logo.png").start_with?("\x89PNG".b)
      assert_equal "media/logo.png", xml_part(zip, "word/_rels/document.xml.rels").at_xpath("//Relationship[@Id='logo']")["Target"]
    end
  end

  test "xlsx includes headers real formulas cached results and column number formats" do
    generate(office_sheet, "xlsx") do |zip|
      workbook = xml_part(zip, "xl/workbook.xml")
      assert_equal [ "Harga", "Checks & dates" ], workbook.xpath("//sheet").map { |node| node["name"] }
      first = xml_part(zip, "xl/worksheets/sheet1.xml")
      assert_equal "Produk", first.at_xpath("//c[@r='A1']//t").text
      assert_equal "ROUND(B2*(1+C2),-2)", first.at_xpath("//c[@r='D2']/f").text
      assert_equal "16800", first.at_xpath("//c[@r='D2']/v").text
      assert_equal "18550.0", first.at_xpath("//c[@r='D4']/v").text
      assert_equal "2", first.at_xpath("//c[@r='B2']")["s"]
      second = xml_part(zip, "xl/worksheets/sheet2.xml")
      assert_equal "VLOOKUP(1234,C2:C2,1,FALSE)", second.at_xpath("//c[@r='D2']/f").text
      assert_equal "1234", second.at_xpath("//c[@r='D2']/v").text
      assert_equal "str", second.at_xpath("//c[@r='D3']")["t"]
      assert_equal "yes & no", second.at_xpath("//c[@r='D3']/v").text
      assert_equal "e", second.at_xpath("//c[@r='D4']")["t"]
      assert_equal "#VALUE!", second.at_xpath("//c[@r='D4']/v").text
      assert_equal "46342", second.at_xpath("//c[@r='A2']/v").text
      styles = xml_part(zip, "xl/styles.xml")
      assert_equal [ "#,##0", '"Rp "#,##0', "0.##%", "dd/mm/yyyy", "@" ], styles.xpath("//numFmt").map { |node| node["formatCode"] }
    end
  end

  test "pptx contains six layouts as separate widescreen slides and editable table" do
    generate(office_slides, "pptx") do |zip|
      presentation = xml_part(zip, "ppt/presentation.xml")
      assert_equal 6, presentation.xpath("//sldId").size
      assert_equal "12192000", presentation.at_xpath("//sldSz")["cx"]
      assert_equal "6858000", presentation.at_xpath("//sldSz")["cy"]
      assert_includes xml_part(zip, "ppt/slides/slide2.xml").text, "12%"
      assert_includes xml_part(zip, "ppt/slides/slide5.xml").text, "Left & <safe>"
      assert_equal 3, xml_part(zip, "ppt/slides/slide6.xml").xpath("//tbl/tr").size
      assert_equal "http://schemas.openxmlformats.org/drawingml/2006/table", xml_part(zip, "ppt/slides/slide6.xml").at_xpath("//graphicData")["uri"]
      assert zip.find_entry("ppt/slideMasters/slideMaster1.xml")
      assert zip.find_entry("ppt/slideLayouts/slideLayout1.xml")
      assert zip.find_entry("ppt/theme/theme1.xml")
    end
  end

  test "empty sheet and table rows and optional slide text produce valid packages" do
    source = { "kind" => "sheet", "tabs" => [ { "name" => "Empty", "columns" => [ { "title" => "A" } ], "rows" => [] } ] }
    generate(source, "xlsx") { |zip| assert_equal 1, xml_part(zip, "xl/worksheets/sheet1.xml").xpath("//row").size }
    generate({ "kind" => "doc", "blocks" => [ { "t" => "table", "head" => [ "A" ], "rows" => [] } ] }, "docx") { |zip| assert zip.find_entry("word/document.xml") }
    generate({ "kind" => "slides", "slides" => [ { "layout" => "title", "title" => "Title" } ] }, "pptx") { |zip| assert zip.find_entry("ppt/slides/slide1.xml") }
  end

  test "invalid sources and mismatched formats are refused" do
    version = ArtifactVersion.new(kind: "doc", content: "{}", design_tokens: {})
    assert_raises(ArgumentError) { ArtifactOffice.generate(version, "xlsx") }
    assert_raises(ArtifactTypes::Invalid) { ArtifactOffice.generate(version, "docx") }
  end

  test "unsupported formula syntax is exported as an error not executable spreadsheet syntax" do
    source = sheet_source
    source["tabs"][0]["rows"][0][3] = { "f" => "=OtherSheet!A1" }
    generate(source, "xlsx") do |zip|
      sheet = xml_part(zip, "xl/worksheets/sheet1.xml")
      assert_nil sheet.at_xpath("//c[@r='D2']/f")
      assert_equal "#VALUE!", sheet.at_xpath("//c[@r='D2']/v").text
      assert_equal "e", sheet.at_xpath("//c[@r='D2']")["t"]
    end
  end

  test "date source cells and copied or calculated dates cache numeric Excel serials" do
    source = { "kind" => "sheet", "tabs" => [ { "name" => "Dates", "columns" => [ { "title" => "Stored", "format" => "date" },
      { "title" => "Copy", "format" => "date" }, { "title" => "Later", "format" => "date" } ],
      "rows" => [ [ "2026-01-01", { "f" => "=A2" }, { "f" => "=B2+7" } ] ] } ] }
    generate(source, "xlsx") do |zip|
      sheet = xml_part(zip, "xl/worksheets/sheet1.xml")
      { "A2" => "46023", "B2" => "46023", "C2" => "46030.0" }.each do |address, serial|
        cell = sheet.at_xpath("//c[@r='#{address}']")
        assert_equal "n", cell["t"]
        assert_equal "4", cell["s"]
        assert_equal serial, cell.at_xpath("v").text
      end
      assert_equal "A2", sheet.at_xpath("//c[@r='B2']/f").text
      assert_equal "B2+7", sheet.at_xpath("//c[@r='C2']/f").text
    end
  end

  test "DOCX and HTML share date formatting for numeric serials ISO text invalid text and blanks" do
    source = { "kind" => "doc", "blocks" => [ { "t" => "table", "head" => %w[Serial ISO Invalid Blank],
      "format" => %w[date date date date], "rows" => [ [ 46342, "2026-11-16", "not a date", nil ] ] } ] }
    version = ArtifactVersion.new(kind: "doc", title: "Dates", content: source.to_json, design_tokens: DesignKit::DEFAULT_TOKENS)
    displayed = Nokogiri::HTML5(ArtifactRendering.html(version)).css("tbody td").map(&:text)
    assert_equal [ "16/11/2026", "16/11/2026", "not a date", "" ], displayed
    generate(source, "docx") do |zip|
      word_cells = xml_part(zip, "word/document.xml").xpath("//tr[2]/tc").map(&:text)
      assert_equal displayed, word_cells
    end
  end
end
