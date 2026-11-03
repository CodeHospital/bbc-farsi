class Admin::TelegramPostsController < Admin::BaseController
  include Pagy::Method

  VIEWS = %w[scheduled history].freeze
  HISTORY_STATUSES = %w[posted error cancelled].freeze

  SORT_COLUMNS = {
    "channel" => "telegram_channels.name",
    "status"  => "telegram_posts.status",
    "posted"  => "telegram_posts.posted_at",
    "created" => "telegram_posts.created_at"
  }.freeze

  def index
    @view     = VIEWS.include?(params[:view]) ? params[:view] : "scheduled"
    @channels = TelegramChannel.order(:name)
    @channel_id = params[:channel_id].presence

    @scheduled_count = TelegramPost.where(status: PostingSchedule::QUEUED_STATUSES).count
    @history_count   = TelegramPost.where(status: HISTORY_STATUSES).count

    @view == "history" ? load_history : load_scheduled
  end

  def show
    @post = TelegramPost.includes(:telegram_channel, translation: :article).find(params[:id])
  end

  # Withdraws a queued post. Only "pending" can be cancelled: the conditional
  # UPDATE loses cleanly to a delivery sweep that just claimed the post.
  def cancel
    post = TelegramPost.find(params[:id])
    cancelled = TelegramPost.where(id: post.id, status: "pending").update_all(status: "cancelled", updated_at: Time.current) == 1

    if cancelled
      redirect_back_or_to admin_telegram_posts_path(view: "scheduled"), notice: "Scheduled post cancelled."
    else
      redirect_back_or_to admin_telegram_posts_path(view: "scheduled"), alert: "Only posts that are still waiting can be cancelled."
    end
  end

  private

  def load_scheduled
    @channel_queues = PostingSchedule.new(channel_id: @channel_id).channel_queues
  end

  def load_history
    history_scope = TelegramPost.where(status: HISTORY_STATUSES)
    history_scope = history_scope.where(telegram_channel_id: @channel_id) if @channel_id
    @status_counts = history_scope.group(:status).count

    history_scope = history_scope.where(status: params[:status]) if HISTORY_STATUSES.include?(params[:status])

    # Newest delivery first by default; failed posts have no posted_at, so fall back to when they last changed.
    column    = SORT_COLUMNS[params[:sort]]
    direction = params[:dir] == "asc" ? "asc" : "desc"
    order     = column ? "#{column} #{direction}, telegram_posts.updated_at desc" : "COALESCE(telegram_posts.posted_at, telegram_posts.updated_at) desc"

    @pagy, @posts = pagy(
      history_scope.eager_load(:telegram_channel).includes(translation: :article).order(Arel.sql(order))
    )
  end
end
