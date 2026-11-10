resource :session, only: %i[new create destroy]
resource :registration, only: %i[new create]
use_doorkeeper do
  skip_controllers :applications, :authorized_applications
  controllers authorizations: "oauth/authorizations"
end
get "/.well-known/oauth-authorization-server", to: "oauth_discovery#authorization_server"
get "/.well-known/oauth-protected-resource", to: "oauth_discovery#protected_resource"
get "/.well-known/oauth-protected-resource/mcp", to: "oauth_discovery#protected_resource"
post "/oauth/register", to: "oauth_registrations#create"
match "/mcp", to: "mcp#handle", via: %i[get post delete]
