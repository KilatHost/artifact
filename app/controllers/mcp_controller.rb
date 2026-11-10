class McpController < ActionController::API
  def handle
    secret = request.authorization.to_s[/\ABearer ([^ ]+)\z/i, 1]
    token = ApiToken.authenticate(secret)
    if token
      workspace = token.workspace
      scopes = token.scopes.split
    elsif secret.present?
      oauth_token = Doorkeeper::AccessToken.by_token(secret)
      if oauth_token&.accessible?
        workspace = User.find_by(id: oauth_token.resource_owner_id)&.workspace
        scopes = oauth_token.scopes.to_a
      end
    end
    unless workspace && scopes.present?
      response.headers["WWW-Authenticate"] = %(Bearer resource_metadata="#{request.base_url}/.well-known/oauth-protected-resource/mcp")
      return render json: { error: "invalid_token" }, status: :unauthorized
    end

    server = MCP::Server.new(name: "kilat", version: "1.0.0", tools: ArtifactMcp::TOOLS, server_context: { workspace: workspace, scopes: scopes, base_url: request.base_url })
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true, enable_json_response: true, serve_subscriptions_listen: false, allowed_hosts: [ request.host_with_port ])
    status, headers, body = transport.call(request.env)
    headers.each { |key, value| response.headers[key] = value unless key.downcase == "content-length" }
    response.headers["Cache-Control"] = "no-store"
    self.status = status
    self.response_body = body
  end
end
