# Sign-in for the worker status page. Sessions are host-only cookies, so the
# worker host needs its own login form; it checks the same User accounts as
# the admin UI (Admin::SessionsController).
class WorkerSessionsController < ApplicationController
  layout "worker_status"

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    flash.now[:alert] = "Too many login attempts. Please wait a few minutes and try again."
    render :new, status: :too_many_requests
  }

  def new
    redirect_to worker_root_path if current_user
  end

  def create
    user = User.authenticate(params[:username], params[:password])

    if user
      reset_session # prevent session fixation: rotate the session id on login
      session[:user_id] = user.id
      redirect_to worker_root_path, notice: "Signed in."
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to worker_root_path, notice: "Signed out."
  end
end
