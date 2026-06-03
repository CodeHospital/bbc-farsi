class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  layout :resolve_layout

  private

  def resolve_layout
    controller_path.start_with?("admin/") ? "admin" : "application"
  end
end
