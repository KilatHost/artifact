class ConnectionsController < ApplicationController
  def index
    @tokens = Current.workspace.api_tokens.order(created_at: :desc)
    @oauth_scopes = granted_oauth_scopes
    @oauth_clients = Doorkeeper::Application.where(id: @oauth_scopes.keys).order(:name)
  end

  def create
    input = params.expect(connection: [ :name, { scopes: [] } ])
    _, @new_token = ApiToken.issue!(workspace: Current.workspace, name: input[:name], scopes: input[:scopes])
    response.headers["Cache-Control"] = "no-store"
    index
    render :index, status: :created
  rescue ActiveRecord::RecordInvalid => error
    redirect_to connections_path, alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    if params[:oauth] == "1"
      application = Doorkeeper::Application.find(params[:id])
      Doorkeeper::AccessToken.revoke_all_for(application.id, Current.user)
      Doorkeeper::AccessGrant.revoke_all_for(application.id, Current.user)
    else
      Current.workspace.api_tokens.find(params[:id]).destroy!
    end
    redirect_to connections_path, notice: "Connection revoked."
  end

  private

  def granted_oauth_scopes
    Doorkeeper::AccessToken.where(resource_owner_id: Current.user.id, revoked_at: nil)
      .select(:application_id, :scopes, :created_at, :expires_in, :refresh_token)
      .reject { |token| token.expired? && token.refresh_token.blank? }
      .group_by(&:application_id)
      .transform_values { |tokens| ApiToken::SCOPES & tokens.flat_map { |token| token.scopes.to_a } }
  end
end
