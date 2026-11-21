require "test_helper"
require_relative "../test_helpers/artifacts"

class ArtifactTypedHtmlTest < ActiveSupport::TestCase
  include ArtifactTestHelpers

  def version(source)
    ArtifactVersion.new(kind: source["kind"], title: "<script>title</script>", content: source.to_json, design_tokens: DesignKit::DEFAULT_TOKENS.merge("accent" => "#123456"))
  end

  test "doc blocks are escaped and formatted using version tokens" do
    source = doc_source
    source["blocks"] += [ { "t" => "paragraph", "text" => "<script>alert(1)</script>" },
      { "t" => "list", "ordered" => true, "items" => [ "<img src=x>" ] }, { "t" => "pagebreak" },
      { "t" => "table", "head" => %w[Integer Percent Date], "format" => %w[int pct date], "rows" => [ [ 1234, 0.25, "2026-11-16" ] ] } ]
    html = ArtifactRendering.html(version(source))
    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute_includes html, "<script>"
    %w[Rp\ 750.000 1.234 25% 16/11/2026 <ol> signature pagebreak size:A4 #123456].each { |text| assert_includes html, text }
  end

  test "sheets display calculated values and allow empty rows" do
    html = ArtifactRendering.html(version(sheet_source))
    assert_includes html, "Rp 16.800"
    assert_includes html, "Rp 18.550"
    assert_includes html, "40%"
    source = sheet_source
    source["tabs"][0]["rows"] = []
    assert_includes ArtifactRendering.html(version(source)), "Harga"
  end

  test "copied date formulas stay formatted as dates while date subtraction gives days" do
    source = { "kind" => "sheet", "tabs" => [ { "name" => "Dates", "columns" => [ { "title" => "Start", "format" => "date" },
      { "title" => "Copy", "format" => "date" }, { "title" => "End", "format" => "date" }, { "title" => "Days" } ],
      "rows" => [ [ "2026-11-16", { "f" => "=A2" }, "2026-11-23", { "f" => "=C2-B2" } ] ] } ] }
    cells = Nokogiri::HTML5(ArtifactRendering.html(version(source))).css("tbody td").map(&:text)
    assert_equal [ "16/11/2026", "16/11/2026", "23/11/2026", "7.0" ], cells
  end

  test "formula allowlist evaluates ranges lookup arithmetic comparisons and lazy IF" do
    tab = { "columns" => %w[Key Value Result].map { |title| { "title" => title } }, "rows" => [ [ "a", 10 ], [ "b", 20 ] ] }
    formulas = { '=VLOOKUP("b",A2:B3,2,FALSE)' => 20, "=SUM(B2:B3)" => 30, "=AVERAGE(B2:B3)" => 15,
      "=COUNT(B2:B3)" => 2, "=MIN(B2:B3)+MAX(B2:B3)" => 30, "=IF(B2< B3,ROUND(10/3,2),1/0)" => 3.33,
      "=IF(2>=1,1,0)+IF(2<>1,1,0)+IF(2=2,1,0)" => 3, "=-(B2*2)+3" => -17, "=A1" => "Key" }
    formulas.each do |formula, expected|
      tab["rows"][0][2] = { "f" => formula }
      assert_equal expected, ArtifactSheetFormulas.new(tab).cell(1, 2), formula
    end
    %w[=C2 =1/0 =SUM( =Z999 =UNKNOWN(1) =1e309 =A2:B3].each do |formula|
      tab["rows"][0][2] = { "f" => formula }
      assert_equal "#ERROR!", ArtifactSheetFormulas.new(tab).cell(1, 2), formula
    end
  end

  test "all slide layouts render and print landscape one per page" do
    source = slides_source
    source["slides"] += [ { "layout" => "two-column", "title" => "<script>", "left" => [ "Left" ], "right" => [] },
      { "layout" => "table", "title" => "Table", "head" => [ "A" ], "rows" => [] } ]
    html = ArtifactRendering.html(version(source))
    assert_equal 6, Nokogiri::HTML5(html).css("section.slide").size
    assert_includes html, "size:320mm 180mm"
    assert_includes html, "break-after:page"
    refute_includes html, "<script>"
  end

  test "typed kinds export JSON sources and PDF via Chromium" do
    %w[doc sheet slides].each do |kind|
      item = version(typed_source(kind))
      assert_equal "json", ArtifactExports.source_extension(item)
      assert ArtifactExports.pdf(item).start_with?("%PDF")
    end
  end

  test "dense slide tables wrap with a content sized font instead of clipping rows" do
    slide = { "layout" => "table", "title" => "Dense table", "head" => Array.new(6, "Long heading " * 15),
      "rows" => Array.new(10) { |r| Array.new(6) { |c| "Row #{r} column #{c}: " + "Long cell content " * 10 } } }
    html = ArtifactRendering.html(version({ "kind" => "slides", "slides" => [ slide ] }))
    section = Nokogiri::HTML5(html).at_css(".slide-table")
    assert_equal 11, section.css("tr").size
    assert_match(/--table-font-size:[3-9](\.5|\.0)?px/, section["style"])
    assert_includes html, "table-layout:fixed"
    assert_includes html, "overflow-wrap:anywhere"
    assert ArtifactExports.pdf(version({ "kind" => "slides", "slides" => [ slide ] })).start_with?("%PDF")
  end
end
