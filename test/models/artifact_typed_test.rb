require "test_helper"
require_relative "../test_helpers/artifacts"

class ArtifactTypedTest < ActiveSupport::TestCase
  include ArtifactTestHelpers

  test "typed versions store canonical JSON and kind changes validate atomically" do
    workspace = User.create!(email: "typed@example.test", password: "a-long-test-password").create_workspace!(name: "Typed")
    artifact = workspace.artifacts.create_draft!(title: "Sheet", kind: "sheet", content: JSON.pretty_generate(sheet_source), author: "Test")
    assert_equal sheet_source.to_json, artifact.current_version.content
    artifact.revise!(expected_version: 1, title: "Text", kind: "markdown", content: "hello", author: "Test")
    error = assert_raises(ActiveRecord::RecordInvalid) do
      artifact.revise!(expected_version: 2, title: "Bad", kind: "doc", content: "{}", author: "Test")
    end
    assert_includes error.message, "Content source.kind"
    assert_equal "markdown", artifact.reload.kind
    assert_equal 2, artifact.versions.count
    artifact.revise!(expected_version: 2, title: "Doc", kind: "doc", content: doc_source.to_json, author: "Test")
    assert_equal "doc", artifact.reload.kind
  end
end
