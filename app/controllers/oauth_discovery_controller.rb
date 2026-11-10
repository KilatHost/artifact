class OauthDiscoveryController < ActionController::API
  def authorization_server
    render json: {
      issuer: request.base_url,
      authorization_endpoint: "#{request.base_url}/oauth/authorize",
      token_endpoint: "#{request.base_url}/oauth/token",
      registration_endpoint: "#{request.base_url}/oauth/register",
      revocation_endpoint: "#{request.base_url}/oauth/revoke",
      response_types_supported: [ "code" ],
      grant_types_supported: %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported: [ "none" ],
      code_challenge_methods_supported: [ "S256" ],
      scopes_supported: ApiToken::SCOPES
    }
  end

  def protected_resource
    render json: { resource: "#{request.base_url}/mcp", authorization_servers: [ request.base_url ], scopes_supported: ApiToken::SCOPES, bearer_methods_supported: [ "header" ] }
  end
end
