class RegistrationsController < ApplicationController
  skip_before_action :require_authentication
  rate_limit to: 5, within: 1.hour, only: :create

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
end
