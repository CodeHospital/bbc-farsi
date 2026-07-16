class ApplicationController < ActionController::Base
  layout :resolve_layout

  before_action :set_paper_trail_whodunnit
  helper_method :current_user

  private

  def resolve_layout
    controller_path.start_with?("admin/") ? "admin" : "application"
  end

  # `active` is checked here (not just at login) so deactivating a user at
  # /admin/users immediately ends any session they already hold.
  def current_user
    @current_user ||= User.active.find_by(id: session[:user_id])
  end
end
