module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    layout "application"
    before_action :require_s256, only: %i[new create]

    private

    def require_s256
      unless params[:code_challenge_method] == "S256" && params[:code_challenge].to_s.match?(/\A[A-Za-z0-9_-]{43}\z/)
        render json: { error: "invalid_request", error_description: "S256 PKCE is required" }, status: :bad_request
      end
    end
  end
end
