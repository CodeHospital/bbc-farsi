# System-wide "who did what" audit trail, backed by PaperTrail::Version —
# every create/update/destroy on a tracked model (Articles, Rewrites,
# Translations, Feeds, Telegram channels, Ollama servers, Users).
class Admin::ActivityLogsController < Admin::BaseController
  before_action :require_admin!
  include Pagy::Method

  def index
    scope = PaperTrail::Version.order(created_at: :desc)
    @item_types = PaperTrail::Version.distinct.order(:item_type).pluck(:item_type)
    scope = scope.where(item_type: params[:item_type]) if params[:item_type].present?
    scope = scope.where(whodunnit: params[:whodunnit]) if params[:whodunnit].present?

    @users = User.order(:username)
    @pagy, @versions = pagy(scope)
  end
end
