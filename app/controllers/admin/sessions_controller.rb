class Admin::SessionsController < ApplicationController
  # The login screen is a self-contained page (its own <html>), so it must NOT
  # be wrapped in the admin layout — otherwise the sidebar menus show up for an
  # unauthenticated visitor on the login page.
  layout false

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    flash.now[:alert] = "Too many login attempts. Please wait a few minutes and try again."
    render :new, status: :too_many_requests
  }

  def new
    redirect_to admin_root_path if logged_in?
  end

  def create
    user = User.authenticate(params[:username], params[:password])

    if user
      reset_session # prevent session fixation: rotate the session id on login
      session[:user_id] = user.id
      redirect_to admin_root_path, notice: "Welcome back."
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to admin_login_path, notice: "Logged out."
  end

  private

  def logged_in?
    session[:user_id].present? && User.active.exists?(id: session[:user_id])
  end
end
