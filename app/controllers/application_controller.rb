class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  layout :resolve_layout

  before_action :set_paper_trail_whodunnit
  helper_method :current_user

  private

  def resolve_layout
    controller_path.start_with?("admin/") ? "admin" : "application"
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
