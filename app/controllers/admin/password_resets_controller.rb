# Public (unauthenticated) "forgot password" flow — not under Admin::BaseController
# since a locked-out user can't log in yet. Tokens are Rails' built-in
# `generates_token_for` (see User#password_reset), so no separate token table
# is needed and a token is invalidated as soon as the password changes.
class Admin::PasswordResetsController < ApplicationController
  layout false

  before_action :set_user_from_token, only: %i[edit update]

  def new; end

  # Always redirects with the same message, whether or not the email matched
  # an account, so this can't be used to enumerate registered users.
  def create
    user = User.active.find_by(email: params[:email].to_s.strip.downcase)
    UserMailer.password_reset(user).deliver_now if user

    redirect_to admin_login_path, notice: "If that email is registered, a password reset link is on its way."
  end

  def edit; end

  def update
    if @user.update(password_params)
      redirect_to admin_login_path, notice: "Password reset — sign in with your new password."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user_from_token
    @user = User.find_by_token_for(:password_reset, params[:token])
    redirect_to new_admin_password_reset_path, alert: "That password reset link is invalid or has expired." unless @user
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
