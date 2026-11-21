require "test_helper"

class ArtifactEditingTest < ActiveSupport::TestCase
  test "Markdown fields exclude syntax the formatted editor cannot round-trip" do
    source = "# Brief\r\n\r\nAn overview.\r\n\r\n- A list item\r\n- **Bold**\r\n\r\n```\r\n# Not a heading\r\n```\r\n\r\n| Metric |\r\n| --- |\r\n| 42 |"

    fields = ArtifactEditing.markdown_fields(source)

    assert_equal [ [ 0, "# ", "Brief" ], [ 2, "", "An overview." ], [ 4, "- ", "A list item" ] ],
      fields.map { |field| field.values_at(:index, :prefix, :text) }
  end

  test "HTML text editing excludes duplicates, markup, and unsafe element types" do
    source = <<~HTML
      <!doctype html><html><body>
      <h1 data-kilat-editable="title" class="headline">Old title</h1>
      <p data-kilat-editable="duplicate">Keep first</p><p data-kilat-editable="duplicate">Keep second</p>
      <p data-kilat-editable="nested"><em>Keep nested</em></p>
      <script data-kilat-editable="script">let keep = true</script>
      <svg><text data-kilat-editable="svg">Keep SVG</text></svg>
      </body></html>
    HTML

    assert_equal({ "title" => "Old title" }, ArtifactEditing.html_fields(source))
    assert_equal source, ArtifactEditing.revise_html(source, { "title" => "Old title" })
    edited = ArtifactEditing.revise_html(source, {
      "title" => "<b>New & safe</b>", "duplicate" => "Never", "nested" => "Never", "script" => "Never", "svg" => "Never"
    })

    assert_includes edited, '<h1 data-kilat-editable="title" class="headline">&lt;b&gt;New &amp; safe&lt;/b&gt;</h1>'
    assert_includes edited, '<script data-kilat-editable="script">let keep = true</script>'
    refute_includes edited, "Never"
  end
end
