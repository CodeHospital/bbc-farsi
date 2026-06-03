class Admin::SessionsController < ApplicationController
  layout "admin"

  def new
    redirect_to admin_root_path if logged_in?
  end

  def create
    expected_user = ENV.fetch("ADMIN_USERNAME")
    expected_pass = ENV.fetch("ADMIN_PASSWORD")

    username_ok = ActiveSupport::SecurityUtils.secure_compare(params[:username].to_s, expected_user)
    password_ok = ActiveSupport::SecurityUtils.secure_compare(params[:password].to_s, expected_pass)

    if username_ok & password_ok
      session[:admin_logged_in] = true
      redirect_to admin_root_path, notice: "Welcome back."
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:admin_logged_in)
    redirect_to admin_login_path, notice: "Logged out."
  end

  private

  def logged_in?
    session[:admin_logged_in] == true
  end
end
