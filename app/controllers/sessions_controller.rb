class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Too many login attempts. Try again later." }

  def new; end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password].to_s) && user.workspace
      destination = session[:return_to].presence || root_path
      reset_session
      session[:user_id] = user.id
      redirect_to destination
    else
      flash.now[:alert] = "Email or password is incorrect."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path, notice: "Signed out."
  end
end
