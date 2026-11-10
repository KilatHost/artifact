Doorkeeper.configure do
  orm :active_record
  resource_owner_authenticator do
    user = User.find_by(id: session[:user_id])
    if user&.workspace
      user
    else
      session[:return_to] = request.fullpath if request.get?
      redirect_to main_app.new_session_path
      nil
    end
  end
  admin_authenticator { head :forbidden }
  grant_flows %w[authorization_code]
  default_scopes :read
  optional_scopes :write, :publish
  enforce_configured_scopes
  force_pkce
  hash_token_secrets
  access_token_expires_in 1.hour
  use_refresh_token
  force_ssl_in_redirect_uri { |uri| !%w[127.0.0.1 [::1] localhost].include?(uri.host) }
end
