class Admin::ArticlesController < Admin::BaseController
  include Pagy::Method

  before_action :set_article, only: %i[show rewrite multi_rewrite translate translate_original multi_translate archive unarchive bump_priority]

  SORT_COLUMNS = {
    "title"     => "articles.title",
    "feed"      => "feeds.name",
    "published" => "articles.published_at",
    "status"    => "articles.status",
    "created"   => "articles.created_at"
  }.freeze

  def index
    new_count = FeedIngestor.run if params[:trigger_fetch]

    base = Article.where(archived: params[:archived] == "1")
    @status_counts = base.group(:status).count
    @feed_counts   = base.group(:feed_id).count

    articles = base.eager_load(:feed) # LEFT JOIN needed for feed-name sort/filter
    articles = articles.where(status: params[:status])   if params[:status].present?
    articles = articles.where(feed_id: params[:feed_id]) if params[:feed_id].present?
    articles = articles.where.not(status: "posted")      if params[:hide_posted] == "1"
    articles = articles.where("LOWER(articles.title) LIKE LOWER(?) OR LOWER(articles.description) LIKE LOWER(?)", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?

    @pagy, @articles = pagy(articles.order(sort_clause))
    @feeds = Feed.order(:name)

    # Preload one published translation per displayed article for portal preview links.
    article_ids = @articles.map(&:id)
    @portal_translation_by_article_id = Translation.completed
      .where(archived: false, article_id: article_ids)
      .where.not(translated_title: [ nil, "" ])
      .order(created_at: :desc)
      .group_by(&:article_id)
      .transform_values(&:first)

    flash.now[:notice] = "Fetched #{new_count} new article(s)." if params[:trigger_fetch]
  end

  def show
    @rewrites       = @article.rewrites.where.not(llm_model: Article::ORIGINAL_REWRITE_MODEL)
                                        .includes(:ollama_server).order(created_at: :desc)
    @translations   = @article.translations.includes(:ollama_server).order(created_at: :desc)
    @ollama_servers = OllamaServer.enabled.order(:name)
    @telegram_channels = TelegramChannel.enabled.order(:name)

    # Best published translation for the portal preview button.
    @portal_translation = @translations.find { |t|
      t.status == "completed" && t.translated_title.present? && !t.archived?
    }

    posted_rows = TelegramPost.where(translation: @translations, status: "posted")
                               .pluck(:translation_id, :telegram_channel_id)
    @posted_channel_ids_by_translation = posted_rows.group_by(&:first)
                                                     .transform_values { |rows| rows.map(&:last) }

    @task_by_target = queue_tasks_by_target
  end

  def rewrite
    server, model = OllamaServer.pick(:rewrite)
    return redirect_to(admin_article_path(@article), alert: "No Ollama servers with rewrite models configured.") unless server
    Task.enqueue_rewrite(@article, server:, model:)
    redirect_to admin_article_path(@article), notice: "Rewrite task created (#{server.name} / #{model})."
  end

  def multi_rewrite
    targets = Array(params[:targets]).reject(&:blank?)
    return redirect_to(admin_article_path(@article), alert: "Select at least one target.") if targets.empty?

    targets.each do |target|
      server_id_str, model = target.split("|", 2)
      server = OllamaServer.find_by(id: server_id_str.to_i)
      Task.enqueue_rewrite(@article, server:, model:, chain_translate: false)
    end
    redirect_to admin_article_path(@article), notice: "#{targets.size} rewrite task(s) created."
  end

  def translate
    rewrite = @article.rewrites.completed.last
    source  = "latest rewrite"
    unless rewrite
      rewrite = @article.original_rewrite!
      source  = "original article"
    end

    server, model = OllamaServer.pick(:translate)
    return redirect_to(admin_article_path(@article), alert: "No Ollama servers with translate models configured.") unless server

    Task.enqueue_translate(rewrite, server:, model:)
    redirect_to admin_article_path(@article), notice: "Translation task created from #{source} (#{server.name} / #{model})."
  end

  def translate_original
    rewrite = @article.original_rewrite!

    server, model = OllamaServer.pick(:translate)
    return redirect_to(admin_article_path(@article), alert: "No Ollama servers with translate models configured.") unless server

    Task.enqueue_translate(rewrite, server:, model:)
    redirect_to admin_article_path(@article), notice: "Translation task created from original article (#{server.name} / #{model})."
  end

  def multi_translate
    targets    = Array(params[:targets]).reject(&:blank?)
    rewrite_id = params[:rewrite_id].presence
    return redirect_to(admin_article_path(@article), alert: "Select at least one target.") if targets.empty?

    rewrite =
      if rewrite_id == "original"
        @article.original_rewrite!
      elsif rewrite_id
        @article.rewrites.find_by(id: rewrite_id)
      else
        @article.rewrites.completed.last || @article.original_rewrite!
      end
    return redirect_to(admin_article_path(@article), alert: "No completed rewrite found.") unless rewrite

    targets.each do |target|
      server_id_str, model = target.split("|", 2)
      server = OllamaServer.find_by(id: server_id_str.to_i)
      Task.enqueue_translate(rewrite, server:, model:, chain_refine: false)
    end
    redirect_to admin_article_path(@article), notice: "#{targets.size} translation task(s) created."
  end

  def bump_priority
    rewrite_tasks     = Task.pending.where(target_type: "Rewrite",
                                           target_id: @article.rewrites.select(:id))
    translation_tasks = Task.pending.where(target_type: "Translation",
                                           target_id: @article.translations.select(:id))
    bumped_count = rewrite_tasks.or(translation_tasks).update_all("priority = priority + 1")
    if bumped_count > 0
      redirect_back fallback_location: admin_articles_path,
                    notice: "Bumped priority on #{bumped_count} pending task(s) for this article."
    else
      redirect_back fallback_location: admin_articles_path,
                    alert: "No pending tasks found for this article."
    end
  end

  def archive
    @article.archive!
    redirect_to admin_articles_path, notice: "Article archived."
  end

  def unarchive
    @article.unarchive!
    redirect_to admin_article_path(@article), notice: "Article unarchived."
  end

  private

  def set_article = @article = Article.find(params[:id])

  # The queue Task driving each rewrite/translation on the show page, keyed by
  # [target_type, target_id] so the view can show priority controls next to a
  # pending task. (One task per target; reruns reuse the same row.)
  def queue_tasks_by_target
    tasks = Task.where(target_type: "Rewrite",     target_id: @rewrites.map(&:id))
            .or(Task.where(target_type: "Translation", target_id: @translations.map(&:id)))
    tasks.index_by { |task| [ task.target_type, task.target_id ] }
  end

  def sort_clause
    column    = SORT_COLUMNS[params[:sort]] || SORT_COLUMNS["created"]
    direction = params[:dir] == "asc" ? "asc" : "desc"
    order     = "#{column} #{direction}"
    order    += ", articles.created_at desc" unless column == SORT_COLUMNS["created"]
    Arel.sql(order)
  end
end
