require "test_helper"
require_relative "../test_helpers/artifacts"

# A1 typed artifacts: sources are checked against config/artifact_types/*.json with the field named, caps hold and only
# the fixed formula list passes.
class ArtifactTypesTest < ActiveSupport::TestCase
  include ArtifactTestHelpers

  test "the three skill examples pass and come back as canonical JSON" do
    %w[doc sheet slides].each do |kind|
      value, json = ArtifactTypes.validate!(kind, typed_source(kind))
      assert_equal typed_source(kind), value
      assert_equal value, JSON.parse(json)
    end
    value, = ArtifactTypes.validate!("doc", JSON.generate(doc_source))
    assert_equal doc_source, value, "a JSON string is accepted too"
    value, = ArtifactTypes.validate!("sheet", sheet_source.deep_symbolize_keys)
    assert_equal sheet_source, value, "symbol keys from an MCP client are normalized"
  end

  test "a wrong source is refused with the field named" do
    assert_refused "source.kind must be \"doc\"", "doc", sheet_source
    assert_refused "source.blocks is required", "doc", { "kind" => "doc" }
    assert_refused "source.blocks[1].text is required", "doc", with_block(doc_source, 1, { "t" => "paragraph" })
    assert_refused "source.blocks[0].level must be at most 3", "doc", with_block(doc_source, 0, { "t" => "heading", "text" => "X", "level" => 4 })
    assert_refused "source.blocks[0].t must be one of: heading, paragraph", "doc", with_block(doc_source, 0, { "t" => "chart" })
    assert_refused "source.blocks[0].color isn't allowed here", "doc", with_block(doc_source, 0, { "t" => "paragraph", "text" => "x", "color" => "red" })
    assert_refused "source.blocks[3].rows[0][1] must be a number", "doc", with_block(doc_source, 3, { "t" => "totals", "rows" => [ [ "Total", "satu juta" ] ] })
    assert_refused "source.blocks[2].rows[0] has 5 cells; the table has 4 columns", "doc",
      with_block(doc_source, 2, { "t" => "table", "head" => %w[A B C D], "rows" => [ [ 1, 2, 3, 4, 5 ] ] })
    assert_refused "source.page must be one of: \"A4\"", "doc", doc_source.merge("page" => "Letter")
    assert_refused "source.tabs[1].name \"harga\" is used by another tab", "sheet",
      sheet_source.merge("tabs" => sheet_source["tabs"] + [ { "name" => "harga", "columns" => [ { "title" => "A" } ], "rows" => [] } ])
    assert_refused "source.tabs[0].rows[0] has 5 cells; the tab has 4 columns", "sheet",
      sheet_source.deep_dup.tap { |source| source["tabs"][0]["rows"][0] << "extra" }
    assert_refused "source.tabs[0].rows[0][3].f is required", "sheet", sheet_source.deep_dup.tap { |source| source["tabs"][0]["rows"][0][3] = { "formula" => "=1" } }
    assert_refused "source.slides[1].layout must be one of: title, bullets, big-number, two-column, table, closing", "slides",
      slides_source.deep_dup.tap { |source| source["slides"][1] = { "layout" => "video" } }
    assert_refused "source.slides[2].bullets has 9 items; the limit is 8", "slides",
      slides_source.deep_dup.tap { |source| source["slides"][2]["bullets"] = Array.new(9, "x") }
    assert_refused "source must be a JSON object; the text sent isn't valid JSON", "doc", "{not json"
    assert_refused "kind must be one of", "chart", {}
  end

  test "caps: doc 200 blocks, sheet 5 tabs of 2,000 rows, slides 40, source 1 MB, logo 200 KB" do
    paragraph = { "t" => "paragraph", "text" => "x" }
    assert ArtifactTypes.validate!("doc", { "kind" => "doc", "blocks" => Array.new(200, paragraph) })
    assert_refused "source.blocks has 201 items; the limit is 200", "doc", { "kind" => "doc", "blocks" => Array.new(201, paragraph) }
    tab = ->(name, rows) { { "name" => name, "columns" => [ { "title" => "A" } ], "rows" => Array.new(rows) { [ 1 ] } } }
    assert ArtifactTypes.validate!("sheet", { "kind" => "sheet", "tabs" => (1..5).map { |n| tab.call("T#{n}", 2_000) } })
    assert_refused "source.tabs has 6 items; the limit is 5", "sheet", { "kind" => "sheet", "tabs" => (1..6).map { |n| tab.call("T#{n}", 1) } }
    assert_refused "source.tabs[0].rows has 2001 items; the limit is 2000", "sheet", { "kind" => "sheet", "tabs" => [ tab.call("T", 2_001) ] }
    slide = { "layout" => "closing", "title" => "Terima kasih" }
    assert ArtifactTypes.validate!("slides", { "kind" => "slides", "slides" => Array.new(40, slide) })
    assert_refused "source.slides has 41 items; the limit is 40", "slides", { "kind" => "slides", "slides" => Array.new(41, slide) }
    big = { "t" => "table", "head" => [ "A" ], "rows" => Array.new(500) { [ "y" * 20 ] } }
    assert_refused "a Doc source is at most 1 MB", "doc", { "kind" => "doc", "blocks" => Array.new(200, big) }
    logo = "data:image/png;base64,#{Base64.strict_encode64('x' * 201.kilobytes)}"
    assert_refused "source.logo is", "doc", doc_source.merge("logo" => logo)
    assert ArtifactTypes.validate!("doc", doc_source.merge("logo" => "data:image/png;base64,#{Base64.strict_encode64('x' * 1_000)}"))
    assert_refused "source.logo isn't in the expected form", "doc", doc_source.merge("logo" => "https://example.com/logo.png")
  end

  test "formulas: only the fixed list, the unsupported one named" do
    ok = [ "=SUM(B2:B9)", "=average(B2:B3)", "=IF(B2>0,ROUND(B2*1.11,0),0)", "=MIN(B2:B3)+MAX(B2:B3)", "=COUNT(B2:B9)",
      "=VLOOKUP(A2,A2:D9,4,FALSE)", "=B2*C2-D2/2", "=IF(A2=\"SUMIF(x)\",1,0)" ]
    ok.each { |formula| assert ArtifactTypes.validate!("sheet", with_formula(formula)), formula }
    assert_refused "source.tabs[0].rows[0][3] uses SUMIF, which Kilat sheets don't support. Use only SUM, AVERAGE, IF, ROUND, MIN, MAX, COUNT, VLOOKUP",
      "sheet", with_formula("=SUMIF(B2:B9,\">0\")")
    assert_refused "uses INDIRECT", "sheet", with_formula("=SUM(INDIRECT(\"B2\"))")
    assert_refused "source.tabs[0].rows[0][3].f isn't in the expected form", "sheet", with_formula("SUM(B2:B3)")
  end

  test "the schema files hold the caps the plan names" do
    assert_equal 200, ArtifactTypes.schema("doc").dig("properties", "blocks", "maxItems")
    assert_equal 5, ArtifactTypes.schema("sheet").dig("properties", "tabs", "maxItems")
    assert_equal 2_000, ArtifactTypes.schema("sheet").dig("$defs", "tab", "properties", "rows", "maxItems")
    assert_equal 40, ArtifactTypes.schema("slides").dig("properties", "slides", "maxItems")
  end

  private
    def assert_refused(message, kind, source)
      error = assert_raises(ArtifactTypes::Invalid) { ArtifactTypes.validate!(kind, source) }
      assert_includes error.message, message
    end

    def with_block(source, index, block)
      source.deep_dup.tap { |copy| copy["blocks"][index] = block }
    end

    def with_formula(formula)
      sheet_source.deep_dup.tap { |source| source["tabs"][0]["rows"][0][3] = { "f" => formula } }
    end
end
