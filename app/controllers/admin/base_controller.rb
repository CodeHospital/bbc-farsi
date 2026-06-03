class Admin::BaseController < ApplicationController
  before_action :require_login

  private

  def require_login
    redirect_to admin_login_path, alert: "Please log in." unless session[:admin_logged_in] == true
  end

  def pagy_defaults
    @pagy_defaults ||= { limit: 30 }
  end
end
