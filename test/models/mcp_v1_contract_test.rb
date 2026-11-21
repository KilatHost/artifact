require "test_helper"

class McpV1ModelContractTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "model-contract@example.test", password: "long-test-password-123")
    @workspace = @user.create_workspace!(name: "Contract")
    @token, = ApiToken.issue!(workspace: @workspace, name: "Agent", scopes: %w[read write])
    @artifact = @workspace.artifacts.create_draft!(title: "Draft", kind: "markdown", content: "v1", author: "MCP")
  end

  test "update and restore receipts replay original results after later edits and reject changed tools or inputs" do
    input = { id: @artifact.id, content: "v2", expected_version: 1, request_id: "update" }
    result = perform("update_artifact", input)
    perform("update_artifact", id: @artifact.id, content: "v3", expected_version: 2)
    assert_equal result, perform("update_artifact", input)
    assert_equal 3, @artifact.versions.count
    assert_raises(ArtifactMcp::IdempotencyMismatch) { perform("update_artifact", input.merge(content: "changed")) }
    assert_raises(ArtifactMcp::IdempotencyMismatch) do
      perform("restore_artifact", id: @artifact.id, version: 1, expected_version: 3, request_id: "update")
    end
    restore = { id: @artifact.id, version: 1, expected_version: 3, request_id: "restore" }
    restored = perform("restore_artifact", restore)
    assert_equal 4, restored["version"]
    assert_equal "v1", @artifact.reload.current_version.content
    assert_equal @token.id, @artifact.current_version.actor_id
    perform("update_artifact", id: @artifact.id, content: "v5", expected_version: 4)
    assert_equal restored, perform("restore_artifact", restore)
    assert_equal 5, @artifact.versions.count
    assert_raises(Artifact::Conflict) { perform("restore_artifact", id: @artifact.id, version: 1, expected_version: 1) }
    assert_raises(ArgumentError) { perform("update_artifact", id: @artifact.id, content: "missing") }
    assert_raises(ArgumentError) { perform("restore_artifact", id: @artifact.id, version: 1) }
  end

  test "old versions have null connection, new versions resist spoofing and history exposes connections" do
    assert_nil perform("get_artifact", id: @artifact.id)["connection"]
    perform("update_artifact", id: @artifact.id, content: "", expected_version: 1, author: "Spoofed", actor_id: 123)
    read = perform("get_artifact", id: @artifact.id)
    assert_equal "", read["content"]
    assert_equal "Agent", read["author"]
    assert_equal @token.id, read["connection"][:id]
    history = perform("artifact_history", id: @artifact.id)
    assert_equal "api_token", history.first["connection"][:type]
    assert_nil history.last["connection"]
    assert_raises(ActiveRecord::ReadOnlyRecord) { @artifact.reload.current_version.update!(author: "changed") }
    assert_empty perform("list_artifacts", offset: 100)
  end

  test "pinned revisions stay private until explicit publication, latest links remain live" do
    previous = ENV["KILAT_PUBLIC_LINKS"]
    ENV["KILAT_PUBLIC_LINKS"] = "latest"
    @artifact.publish!
    assert_nil @artifact.public_version_number
    ENV["KILAT_PUBLIC_LINKS"] = "pinned"
    perform("update_artifact", id: @artifact.id, content: "v2", expected_version: 1)
    assert_equal 2, @artifact.reload.public_version.number, "existing null-pin publications still follow latest"
    @artifact.publish!
    assert_equal 2, @artifact.public_version_number
    perform("update_artifact", id: @artifact.id, content: "v3", expected_version: 2)
    assert_equal 2, @artifact.reload.public_version.number
    perform("publish_artifact", id: @artifact.id)
    assert_equal 3, @artifact.reload.public_version_number
    @artifact.unpublish!
    assert_nil @artifact.public_version
    assert_nil @artifact.public_version_number
  ensure
    ENV["KILAT_PUBLIC_LINKS"] = previous
  end

  private

  def perform(name, input)
    ArtifactMcp.perform(name, @workspace, input, actor: @token)
  end
end
