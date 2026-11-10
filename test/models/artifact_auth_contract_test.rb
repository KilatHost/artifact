require "test_helper"

class ArtifactAuthContractTest < ActiveSupport::TestCase
  test "API token secrets are hashed and revocable" do
    user = User.create!(email: "token-check@example.test", password: "a-long-test-password")
    workspace = user.create_workspace!(name: "Test")
    token, secret = ApiToken.issue!(workspace: workspace, name: "Check", scopes: [ "read" ])
    assert_not_equal secret, token.token_digest
    assert_equal token, ApiToken.authenticate(secret)
    assert_nil ApiToken.authenticate("kilat_wrong")
    token.destroy!
    assert_nil ApiToken.authenticate(secret)
  end

  test "MCP enforces scopes and tenant boundaries" do
    first = User.create!(email: "first-check@example.test", password: "a-long-test-password").create_workspace!(name: "First")
    second = User.create!(email: "second-check@example.test", password: "a-long-test-password").create_workspace!(name: "Second")
    artifact = first.artifacts.create_draft!(title: "Private", kind: "document", content: "secret", author: "Test")
    assert_raises(ActiveRecord::RecordNotFound) { ArtifactMcp.perform("get_artifact", second, { id: artifact.id }) }
    tool = ArtifactMcp::TOOLS.find { |entry| entry.name_value == "publish_artifact" }
    response = tool.call(id: artifact.id, server_context: { workspace: first, scopes: [ "write" ] })
    assert response.error?
    assert_nil artifact.reload.published_version_id
  end

  test "MCP create retries return original artifact and reject changed input" do
    workspace = User.create!(email: "retry-check@example.test", password: "a-long-test-password").create_workspace!(name: "Retry")
    input = { request_id: "stable-request", title: "Draft", kind: "markdown", content: "Hello" }
    first = ArtifactMcp.perform("create_artifact", workspace, input.dup)
    repeated = ArtifactMcp.perform("create_artifact", workspace, input.dup)
    assert_equal first["id"], repeated["id"]
    assert_equal 1, workspace.artifacts.count
    assert_raises(ArgumentError) { ArtifactMcp.perform("create_artifact", workspace, input.merge(content: "Changed")) }
  end
end
