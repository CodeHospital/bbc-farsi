class Admin::SessionsController < ApplicationController
  # The login screen is a self-contained page (its own <html>), so it must NOT
  # be wrapped in the admin layout — otherwise the sidebar menus show up for an
  # unauthenticated visitor on the login page.
  layout false

  def new
    redirect_to admin_root_path if logged_in?
  end

  def create
    user = User.authenticate(params[:username], params[:password])

    if user
      session[:user_id] = user.id
      redirect_to admin_root_path, notice: "Welcome back."
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to admin_login_path, notice: "Logged out."
  end

  private

  def logged_in?
    session[:user_id].present? && User.exists?(id: session[:user_id])
  end
end
