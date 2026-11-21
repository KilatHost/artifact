require "test_helper"

class McpV1ContractTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "v1-owner@example.test", password: "long-test-password-123")
    @workspace = @owner.create_workspace!(name: "Owner")
    @other = User.create!(email: "v1-other@example.test", password: "long-test-password-123")
    @other_workspace = @other.create_workspace!(name: "Other")
    @a, @a_secret = ApiToken.issue!(workspace: @workspace, name: "Claude Code", scopes: %w[read write publish])
    @b, @b_secret = ApiToken.issue!(workspace: @workspace, name: "Codex", scopes: %w[read write])
    @previous_mode = ENV["KILAT_PUBLIC_LINKS"]
    ENV["KILAT_PUBLIC_LINKS"] = "pinned"
  end

  teardown do
    ENV["KILAT_PUBLIC_LINKS"] = @previous_mode
  end

  test "independent agents and owner edit one stable artifact with safe retries and explicit public pins" do
    created = call_tool(@a_secret, "create_artifact", request_id: "create", title: "Shared", kind: "markdown", content: "agent A")
    artifact = Artifact.find(created.fetch("id"))
    assert_equal "Claude Code", artifact.current_version.author
    assert_equal "api_token", artifact.current_version.actor_type
    assert_equal @a.id, artifact.current_version.actor_id

    post session_path, params: { email: @owner.email, password: "long-test-password-123" }
    patch artifact_path(artifact), params: { artifact: { title: "Shared", kind: "markdown", content: "owner edit", expected_version: 1 } }
    assert_response :redirect
    assert_equal "user", artifact.reload.current_version.actor_type
    assert_equal @owner.id, artifact.current_version.actor_id
    read = call_tool(@b_secret, "get_artifact", id: artifact.id)
    assert_equal "owner edit", read["content"]
    assert_equal({ "type" => "user", "id" => @owner.id, "name" => @owner.email }, read["connection"])

    revise = { id: artifact.id, content: "agent B", expected_version: read["version"], request_id: "revise" }
    revised = call_tool(@b_secret, "update_artifact", **revise)
    assert_equal 3, revised["version"]
    read = call_tool(@b_secret, "get_artifact", id: artifact.id)
    assert_equal "Codex", read["author"]
    assert_equal({ "type" => "api_token", "id" => @b.id, "name" => "Codex" }, read["connection"])
    assert_equal revised, call_tool(@b_secret, "update_artifact", **revise)
    assert_equal 3, artifact.versions.count
    conflict = call_tool(@a_secret, "update_artifact", id: artifact.id, content: "stale", expected_version: 1, error: "version_conflict")
    assert_equal 3, conflict["current_version"]
    assert_includes conflict["recovery"], "get_artifact"

    foreign, foreign_secret = ApiToken.issue!(workspace: @other_workspace, name: "Foreign", scopes: %w[read write])
    assert foreign.persisted?
    call_tool(foreign_secret, "get_artifact", id: artifact.id, error: "not_found")
    call_tool(foreign_secret, "update_artifact", id: artifact.id, content: "theft", expected_version: 3, error: "not_found")
    @b.destroy!
    rpc(@b_secret, "get_artifact", id: artifact.id)
    assert_response :unauthorized

    assert_equal 3, call_tool(@a_secret, "publish_artifact", id: artifact.id)["public_version"]
    call_tool(@a_secret, "update_artifact", id: artifact.id, content: "unpublished v4", expected_version: 3)
    public_client = open_session
    public_client.get public_artifact_path(artifact.public_id)
    assert_equal 200, public_client.response.status
    assert_includes public_client.response.headers["Cache-Control"], "no-store"
    public_client.get public_artifact_frame_path(artifact.public_id)
    assert_includes public_client.response.body, "agent B"
    refute_includes public_client.response.body, "unpublished v4"
    assert_includes public_client.response.headers["Cache-Control"], "no-store"
    get artifact_path(artifact)
    assert_select "button", text: "Update public link"
    other_client = open_session
    other_client.post session_path, params: { email: @other.email, password: "long-test-password-123" }
    other_client.post update_public_link_artifact_path(artifact)
    assert_equal 404, other_client.response.status
    post update_public_link_artifact_path(artifact)
    assert_response :redirect
    public_client.get public_artifact_frame_path(artifact.public_id)
    assert_includes public_client.response.body, "unpublished v4"
    public_client.get public_artifact_download_path(artifact.public_id, export_format: "html")
    assert_includes public_client.response.body, "unpublished v4"
    assert_includes public_client.response.headers["Cache-Control"], "no-store"
    call_tool(@a_secret, "unpublish_artifact", id: artifact.id)
    assert_nil artifact.reload.public_version_number
    public_client.get public_artifact_path(artifact.public_id)
    assert_equal 302, public_client.response.status
    assert_equal new_session_url, public_client.response.location
    refute_includes public_client.response.body, "unpublished v4"
    public_client.post session_path, params: { email: @owner.email, password: "long-test-password-123" }
    assert_equal public_artifact_url(artifact.public_id), public_client.response.location
    public_client = open_session
    [ public_artifact_frame_path(artifact.public_id),
      public_artifact_file_path(artifact.public_id), public_artifact_download_path(artifact.public_id, export_format: "html") ].each do |path|
      public_client.get path
      assert_equal 404, public_client.response.status
    end
  end

  test "retry receipts cannot be reused by another authenticated connection" do
    create = { request_id: "shared-create", title: "Shared", kind: "markdown", content: "v1" }
    created = call_tool(@a_secret, "create_artifact", **create)
    call_tool(@b_secret, "create_artifact", **create, error: "idempotency_mismatch")
    revise = { id: created["id"], content: "v2", expected_version: 1, request_id: "shared-revise" }
    revised = call_tool(@a_secret, "update_artifact", **revise)
    call_tool(@b_secret, "update_artifact", **revise, error: "idempotency_mismatch")
    assert_equal revised, call_tool(@a_secret, "update_artifact", **revise)
    restore = { id: created["id"], version: 1, expected_version: 2, request_id: "shared-restore" }
    restored = call_tool(@a_secret, "restore_artifact", **restore)
    call_tool(@b_secret, "restore_artifact", **restore, error: "idempotency_mismatch")
    assert_equal restored, call_tool(@a_secret, "restore_artifact", **restore)
    assert_equal 3, Artifact.find(created["id"]).versions.count
  end

  test "required inputs, scopes and validation have JSON errors" do
    created = call_tool(@a_secret, "create_artifact", request_id: "create", title: "Shared", kind: "markdown", content: "v1")
    call_tool(@a_secret, "update_artifact", id: created["id"], content: "missing version", error: "invalid_request")
    call_tool(@a_secret, "restore_artifact", id: created["id"], version: 1, error: "invalid_request")
    call_tool(@a_secret, "update_artifact", id: created["id"], content: "v2", expected_version: 1, request_id: "", error: "invalid_request")
    call_tool(@a_secret, "create_artifact", request_id: "invalid", title: "", kind: "markdown", content: "", error: "invalid_request")
    denied = call_tool(@b_secret, "publish_artifact", id: created["id"], error: "permission_denied")
    assert_equal "publish", denied["required_scope"]
    call_tool(@a_secret, "create_artifact", request_id: "create", title: "Changed", kind: "markdown", content: "v1", error: "idempotency_mismatch")
  end

  test "public file downloads stay pinned and become unavailable after unpublish" do
    first = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("original file"), filename: "first.txt", content_type: "text/plain")
    second = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("new private file"), filename: "second.txt", content_type: "text/plain")
    artifact = @workspace.artifacts.create_draft!(title: "File", kind: "file", content: "", author: @owner.email, actor: @owner, file: first)
    artifact.publish!
    artifact.revise!(expected_version: 1, title: "File", content: "", author: @owner.email, actor: @owner, file: second)
    get public_artifact_file_path(artifact.public_id)
    assert_response :success
    assert_equal "original file", response.body
    assert_includes response.headers["Cache-Control"], "no-store"
    artifact.update_public_link!
    get public_artifact_file_path(artifact.public_id)
    assert_equal "new private file", response.body
    artifact.unpublish!
    get public_artifact_file_path(artifact.public_id)
    assert_response :not_found
  end

  test "OAuth application attribution and default scope selection" do
    post "/oauth/register", params: { client_name: "OAuth Agent", redirect_uris: [ "https://client.example/cb" ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :created
    assert_equal "read write", JSON.parse(response.body)["scope"]
    assert_equal %w[read write], Doorkeeper.configuration.default_scopes.to_a
    app = Doorkeeper::Application.find_by!(uid: JSON.parse(response.body)["client_id"])
    token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: @owner.id, scopes: "read write", expires_in: 3600)
    secret = token.plaintext_token
    result = call_tool(secret, "create_artifact", request_id: "oauth", title: "OAuth", kind: "markdown", content: "hello")
    read = call_tool(secret, "get_artifact", id: result["id"])
    assert_equal({ "type" => "oauth_application", "id" => app.id, "name" => app.name }, read["connection"])
    post session_path, params: { email: @owner.email, password: "long-test-password-123" }
    get connections_path
    %w[read write].each { |scope| assert_select "input#scope-#{scope}[checked]" }
    assert_select "input#scope-publish[checked]", count: 0
  end

  private

  def rpc(secret, name, **arguments)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "Authorization" => "Bearer #{secret}" }
  end

  def call_tool(secret, name, error: nil, **arguments)
    rpc(secret, name, **arguments)
    assert_response :success
    result = JSON.parse(response.body).fetch("result")
    assert_equal error.present?, result.fetch("isError")
    output = JSON.parse(result.fetch("content").first.fetch("text"))
    assert_equal error, output["error"] if error
    output
  end
end
