require "test_helper"

class ArtifactSheetFormulasTest < ActiveSupport::TestCase
  def evaluate(formula, rows: [ [ nil, nil ] ], columns: [ { "title" => "Input" }, { "title" => "Blank" } ])
    tab = { "columns" => columns + [ { "title" => "Result" } ], "rows" => rows.deep_dup }
    tab["rows"][0][columns.length] = { "f" => formula }
    ArtifactSheetFormulas.new(tab).cell(1, columns.length)
  end

  test "blank cells are zero for arithmetic and numeric comparisons and empty for string comparisons" do
    { "=IF(B2=0,0,100)" => 0, "=B2+5" => 5, "=5-B2" => 5, "=B2*5" => 0,
      "=B2<1" => true, "=1>B2" => true, "=B2>=0" => true, "=0<=B2" => true,
      '=B2=""' => true, '=""=B2' => true, '=B2<>""' => false,
      '=B2="text"' => false, "=A2=B2" => true }.each do |formula, expected|
      assert_equal expected, evaluate(formula), formula
    end
  end

  test "date formatted ISO references and ranges use Excel serials without changing rendered cells" do
    columns = [ { "title" => "End", "format" => "date" }, { "title" => "Start", "format" => "date" } ]
    rows = [ [ "2026-11-23", "2026-11-16" ] ]
    assert_equal 7, evaluate("=A2-B2", rows: rows, columns: columns)
    assert_equal 46342, evaluate("=B2+0", rows: rows, columns: columns)
    assert_equal 92691, evaluate("=SUM(A2:B2)", rows: rows, columns: columns)
    assert_equal "#ERROR!", evaluate("=A2-B2", rows: rows)
    assert_equal "#ERROR!", evaluate("=A2+0", rows: [ [ "not a date", nil ] ], columns: columns)
    assert_equal "2026-11-23", ArtifactSheetFormulas.new({ "columns" => columns, "rows" => rows }).cell(1, 0)
  end

  test "aggregate ranges past stored rows ignore missing blank cells" do
    rows = [ [ 10, nil ], [ 20, nil ] ]
    { "SUM" => 30, "AVERAGE" => 15, "MIN" => 10, "MAX" => 20, "COUNT" => 2 }.each do |function, expected|
      assert_equal expected, evaluate("=#{function}(A2:A100)", rows: rows), function
    end
    assert_equal(-10, evaluate("=MAX(A2:A100)", rows: [ [ -10, nil ] ]))
    assert_equal 0, evaluate("=SUM(A99:A1048576)", rows: rows)
    assert_equal 0, evaluate("=COUNT(A99:A1048576)", rows: rows)
    assert_equal "#ERROR!", evaluate("=AVERAGE(A99:A100)", rows: rows)
    assert_equal "#ERROR!", evaluate("=SUM(A5:A2)", rows: rows)
    assert_equal "#ERROR!", evaluate("=SUM(A2:A1048577)", rows: rows)
  end
end
