class Admin::TelegramPostsController < Admin::BaseController
  include Pagy::Method

  SORT_COLUMNS = {
    "channel" => "telegram_channels.name",
    "status"  => "telegram_posts.status",
    "posted"  => "telegram_posts.posted_at",
    "created" => "telegram_posts.created_at"
  }.freeze

  def index
    column    = SORT_COLUMNS[params[:sort]] || SORT_COLUMNS["created"]
    direction = params[:dir] == "asc" ? "asc" : "desc"
    order     = "#{column} #{direction}"
    order    += ", telegram_posts.created_at desc" unless column == SORT_COLUMNS["created"]

    @pagy, @posts = pagy(
      TelegramPost.eager_load(:telegram_channel).includes(:translation).order(Arel.sql(order))
    )
  end

  def show
    @post = TelegramPost.includes(:translation, :telegram_channel).find(params[:id])
  end
end
