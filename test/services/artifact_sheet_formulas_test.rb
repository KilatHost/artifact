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
end
