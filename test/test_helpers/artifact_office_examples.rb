require_relative "artifacts"

module ArtifactOfficeExamples
  include ArtifactTestHelpers

  def office_doc
    doc_source.deep_dup.tap do |source|
      source["logo"] = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5n8AAAAASUVORK5CYII="
      source["blocks"] += [ { "t" => "paragraph", "text" => "<script>Not markup & still text</script>\nSecond line" },
        { "t" => "list", "ordered" => true, "items" => [ "First item", "Second item" ] },
        { "t" => "list", "items" => [ "A bullet" ] }, { "t" => "pagebreak" },
        { "t" => "table", "head" => %w[Integer Percent Date Text], "format" => %w[int pct date text], "rows" => [ [ 1234, 0.25, "2026-11-16", "A&B" ] ] } ]
    end
  end

  def office_sheet
    sheet_source.deep_dup.tap do |source|
      source["tabs"] << { "name" => "Checks & dates", "columns" => [ { "title" => "Date", "format" => "date" }, { "title" => "Text", "format" => "text" },
        { "title" => "Integer", "format" => "int" }, { "title" => "Result" } ],
        "rows" => [ [ "2026-11-16", "<script>&", 1234, { "f" => "=VLOOKUP(1234,C2:C2,1,FALSE)" } ],
          [ nil, true, nil, { "f" => '=IF(TRUE,"yes & no","no")' } ],
          [ nil, false, nil, { "f" => "=1/0" } ] ] }
    end
  end

  def office_slides
    slides_source.deep_dup.tap do |source|
      source["slides"] += [ { "layout" => "two-column", "title" => "Two columns", "left" => [ "Left & <safe>" ], "right" => [ "Right" ] },
        { "layout" => "table", "title" => "Sales table", "head" => [ "Product", "Sales" ], "rows" => [ [ "Keripik", 1234 ], [ "Sambal" ] ] } ]
    end
  end
end
