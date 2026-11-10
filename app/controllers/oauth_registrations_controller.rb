require "uri"

class OauthRegistrationsController < ActionController::API
  rate_limit to: 20, within: 1.hour, only: :create

  def create
    redirects = params[:redirect_uris]
    valid = redirects.is_a?(Array) && redirects.length.between?(1, 5) && redirects.all? { |value| safe_redirect?(value) }
    valid &&= params[:token_endpoint_auth_method].in?([ nil, "none" ])
    valid &&= params[:grant_types].nil? || params[:grant_types] == [ "authorization_code" ] || params[:grant_types] == %w[authorization_code refresh_token]
    valid &&= params[:response_types].nil? || params[:response_types] == [ "code" ]
    scopes = params.fetch(:scope, "read").to_s.split.uniq
    valid &&= scopes.any? && (scopes - ApiToken::SCOPES).empty?
    name = params[:client_name].to_s.strip
    valid &&= name.length.between?(1, 100)
    return render json: { error: "invalid_client_metadata" }, status: :bad_request unless valid

    application = Doorkeeper::Application.create!(name: name, redirect_uri: redirects.uniq.join("\n"), scopes: scopes.join(" "), confidential: false)
    response.headers["Cache-Control"] = "no-store"
    render json: { client_id: application.uid, client_id_issued_at: application.created_at.to_i, client_name: application.name, redirect_uris: redirects.uniq, token_endpoint_auth_method: "none", grant_types: %w[authorization_code refresh_token], response_types: [ "code" ], scope: application.scopes.to_s }, status: :created
  rescue ActiveRecord::RecordInvalid
    render json: { error: "invalid_redirect_uri" }, status: :bad_request
  end

  private

  def safe_redirect?(value)
    return false unless value.is_a?(String) && value.bytesize <= 2048 && !value.match?(/[\s\\]/)
    uri = URI.parse(value)
    return false if uri.host.blank? || uri.userinfo || uri.fragment || uri.host.include?("*")
    uri.scheme == "https" || (uri.scheme == "http" && %w[127.0.0.1 [::1] localhost].include?(uri.host))
  rescue URI::InvalidURIError
    false
  end
end
