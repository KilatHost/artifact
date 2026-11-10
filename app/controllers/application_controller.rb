class ApplicationController < ActionController::Base
  before_action :require_authentication
  around_action :with_current_identity

  private

  def with_current_identity
    Current.user = User.find_by(id: session[:user_id])
    Current.workspace = Current.user&.workspace
    yield
  ensure
    Current.reset
  end

  def require_authentication
    user = User.find_by(id: session[:user_id])
    return if user&.workspace

    session[:return_to] = request.fullpath if request.get? || request.head?
    redirect_to new_session_path
  end
end
