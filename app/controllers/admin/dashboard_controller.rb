# Admin home: what happened in the last day, what needs a human, how the
# pipeline and task queue look, and the latest articles and posts.
class Admin::DashboardController < Admin::BaseController
  ACTIVITY_DAYS   = 7
  RECENT_LIMIT    = 8
  PIPELINE_STAGES = %w[pending rewriting rewritten translating translated posted error].freeze

  def index
    current_time = Time.current

    @kpi_tiles        = build_kpi_tiles(current_time)
    @attention_items  = build_attention_items(current_time)
    @pipeline_counts  = Article.not_archived.group(:status).count
    @pipeline_total   = PIPELINE_STAGES.sum { |stage| @pipeline_counts[stage].to_i }
    @task_queue       = build_task_queue(current_time)
    @daily_activity   = build_daily_activity(current_time)
    @totals           = {
      feeds:             Feed.count,
      articles:          Article.count,
      rewrites:          Rewrite.count,
      translations:      Translation.count,
      telegram_channels: TelegramChannel.count,
      telegram_posts:    TelegramPost.count
    }
    @recent_articles  = Article.includes(:feed).order(created_at: :desc).limit(RECENT_LIMIT)
    @recent_posts     = TelegramPost.includes(:telegram_channel, translation: :article)
                                    .order(created_at: :desc).limit(RECENT_LIMIT)
  end

  private

  # Last 24 hours, compared with the 24 hours before that.
  def build_kpi_tiles(current_time)
    last_day     = (current_time - 24.hours)..current_time
    previous_day = (current_time - 48.hours)...(current_time - 24.hours)

    [
      kpi_tile("Articles ingested", "bi-newspaper", "primary", admin_articles_path) { |range| Article.where(created_at: range).count },
      kpi_tile("Posts sent", "bi-send-check", "success", admin_telegram_posts_path(view: "history")) { |range| TelegramPost.where(status: "posted", posted_at: range).count },
      kpi_tile("Story views", "bi-eye", "info", admin_analytics_path) { |range| ArticleView.where(created_at: range).count },
      kpi_tile("Tasks completed", "bi-cpu", "secondary", admin_tasks_path(status: "completed")) { |range| Task.where(status: "completed", completed_at: range).count }
    ].map do |tile|
      tile.merge(current_value: tile[:counter].call(last_day), previous_value: tile[:counter].call(previous_day)).except(:counter)
    end
  end

  def kpi_tile(label, icon, color, path, &counter)
    { label:, icon:, color:, path:, counter: }
  end

  # Only non-zero items are shown; an empty list renders an "all clear" note.
  def build_attention_items(current_time)
    items = [
      { label: "Articles with errors", count: Article.not_archived.where(status: "error").count,
        path: admin_articles_path(status: "error"), icon: "bi-exclamation-octagon", tone: "danger" },
      { label: "Failed tasks (24h)", count: Task.where(status: "failed", updated_at: (current_time - 24.hours)..).count,
        path: admin_tasks_path(status: "failed"), icon: "bi-x-circle", tone: "danger" },
      { label: "Post errors", count: TelegramPost.where(status: "error").count,
        path: admin_telegram_posts_path(view: "history", status: "error"), icon: "bi-send-x", tone: "danger" },
      { label: "Stale task claims", count: Task.stale.count,
        path: admin_tasks_path(status: "claimed"), icon: "bi-hourglass-split", tone: "warning" },
      { label: "Translations needing edit", count: helpers.manual_edit_review_count,
        path: admin_translations_path(needs_manual_edit: "1"), icon: "bi-pencil-fill", tone: "warning" },
      { label: current_user&.can_review_edits? ? "Edits awaiting review" : "My pending edits",
        count: helpers.pending_edit_sidebar_count,
        path: admin_pending_edits_path, icon: "bi-check2-square", tone: "warning" }
    ]
    items.select { |item| item[:count].positive? }
  end

  def build_task_queue(current_time)
    open_counts_by_kind_and_status = Task.where(status: %w[pending claimed]).group(:kind, :status).count
    oldest_pending_created_at      = Task.pending.minimum(:created_at)

    {
      pending:            open_counts_by_kind_and_status.select { |(_kind, status), _count| status == "pending" }.values.sum,
      claimed:            open_counts_by_kind_and_status.select { |(_kind, status), _count| status == "claimed" }.values.sum,
      oldest_pending_age: oldest_pending_created_at && (current_time - oldest_pending_created_at),
      by_kind:            Task::KINDS.filter_map do |kind|
        pending_count = open_counts_by_kind_and_status.fetch([ kind, "pending" ], 0)
        claimed_count = open_counts_by_kind_and_status.fetch([ kind, "claimed" ], 0)
        { kind:, pending: pending_count, claimed: claimed_count } if (pending_count + claimed_count).positive?
      end
    }
  end

  # One row per calendar day (oldest first). Bucketed in Ruby so it works the
  # same on SQLite and Postgres and respects the app time zone.
  def build_daily_activity(current_time)
    first_day   = (current_time.to_date - (ACTIVITY_DAYS - 1))
    window      = first_day.beginning_of_day..current_time
    ingested_by_day = Article.where(created_at: window).pluck(:created_at).map(&:to_date).tally
    posted_by_day   = TelegramPost.where(status: "posted", posted_at: window).pluck(:posted_at).map(&:to_date).tally

    (first_day..current_time.to_date).map do |day|
      { date: day, ingested: ingested_by_day.fetch(day, 0), posted: posted_by_day.fetch(day, 0) }
    end
  end
end
