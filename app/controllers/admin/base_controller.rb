class Admin::BaseController < ApplicationController
  before_action :require_login

  private

  def require_login
    redirect_to admin_login_path, alert: "Please log in." unless current_user
  end

  # Restricts an action to admins; editors get redirected with an alert.
  # Add as a `before_action :require_admin!` in controllers that manage
  # infrastructure/configuration rather than editorial content.
  def require_admin!
    redirect_to admin_root_path, alert: "You don't have permission to do that." unless current_user&.admin?
  end

  def pagy_defaults
    @pagy_defaults ||= { limit: 30 }
  end
end
