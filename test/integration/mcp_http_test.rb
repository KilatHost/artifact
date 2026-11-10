require "test_helper"

class McpHttpTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "http-#{SecureRandom.hex(6)}@example.test", password: "test-password-long-enough")
    @workspace = @owner.create_workspace!(name: "HTTP")
  end

  test "HTTP MCP authenticates, initializes and serves tools without leaking private data" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], "resource_metadata"
    token, secret = ApiToken.issue!(workspace: @workspace, name: "HTTP", scopes: [ "read" ])
    headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "Authorization" => "Bearer #{secret}" }
    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "initialize", params: { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "Check", version: "1" } } }.to_json, headers: headers
    assert_response :success
    assert_equal "kilat", JSON.parse(response.body).dig("result", "serverInfo", "name")
    post "/mcp", params: { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "list_artifacts", arguments: {} } }.to_json, headers: headers
    assert_response :success
    refute JSON.parse(response.body).dig("result", "isError")
    token.destroy!
    post "/mcp", params: { jsonrpc: "2.0", id: 4, method: "tools/list" }.to_json, headers: headers
    assert_response :unauthorized
  end

  test "OAuth public client uses consent and S256 PKCE to obtain scoped token" do
    post "/oauth/register", params: { client_name: "Local test", redirect_uris: [ "http://127.0.0.1:4321/callback" ], token_endpoint_auth_method: "none", grant_types: [ "authorization_code", "refresh_token" ], response_types: [ "code" ], scope: "read write" }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :created
    client_id = JSON.parse(response.body).fetch("client_id")
    post session_path, params: { email: @owner.email, password: "test-password-long-enough" }
    assert_response :redirect
    verifier = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    fields = { client_id: client_id, redirect_uri: "http://127.0.0.1:4321/callback", response_type: "code", scope: "read write", code_challenge: challenge, code_challenge_method: "S256", state: "opaque" }
    get "/oauth/authorize", params: fields
    assert_response :success
    post "/oauth/authorize", params: fields
    assert_response :redirect
    code = Rack::Utils.parse_query(URI(response.location).query).fetch("code")
    post "/oauth/token", params: { grant_type: "authorization_code", client_id: client_id, code: code, redirect_uri: fields[:redirect_uri], code_verifier: verifier }
    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "read write", payload.fetch("scope")
    token = Doorkeeper::AccessToken.by_token(payload.fetch("access_token"))
    assert_equal @owner.id, token.resource_owner_id
    refute_includes token.scopes, "publish"
  end
end
