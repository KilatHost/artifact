class RegistrationsController < ApplicationController
  skip_before_action :require_authentication
  rate_limit to: 5, within: 1.hour, only: :create
  before_action :require_open_signup

  # The first account is always allowed; after that only with ALLOW_SIGNUP=true, so a public
  # instance doesn't become anyone's page host.
  def self.open?
    !User.exists? || ENV["ALLOW_SIGNUP"] == "true"
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[email password password_confirmation]))
    User.transaction do
      @user.save!
      @user.create_workspace!(name: "My workspace")
    end
    reset_session
    session[:user_id] = @user.id
    redirect_to root_path
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    @user.errors.add(:email, "could not be registered") if @user.errors.empty?
    render :new, status: :unprocessable_entity
  end

  private

  def require_open_signup
    redirect_to new_session_path, alert: "Sign-up is closed on this server. Ask its owner for an account." unless self.class.open?
  end
end
