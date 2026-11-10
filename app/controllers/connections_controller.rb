class ConnectionsController < ApplicationController
  def index
    @tokens = Current.workspace.api_tokens.order(created_at: :desc)
    @oauth_clients = Doorkeeper::Application.where(id: Doorkeeper::AccessToken.where(resource_owner_id: Current.user.id, revoked_at: nil).select(:application_id)).order(:name)
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
end
