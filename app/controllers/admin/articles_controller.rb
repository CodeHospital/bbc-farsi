class Admin::ArticlesController < Admin::BaseController
  include Pagy::Backend

  before_action :set_article, only: %i[show rewrite multi_rewrite translate translate_original multi_translate archive unarchive]

  def index
    new_count = FeedIngestor.run if params[:trigger_fetch]

    base = Article.where(archived: params[:archived] == "1")
    @status_counts = base.group(:status).count
    @feed_counts   = base.group(:feed_id).count

    articles = base.includes(:feed)
    articles = articles.where(status: params[:status])   if params[:status].present?
    articles = articles.where(feed_id: params[:feed_id]) if params[:feed_id].present?
    articles = articles.where("title LIKE ? OR description LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?

    @pagy, @articles = pagy(articles.order(created_at: :desc))
    @feeds = Feed.order(:name)
    flash.now[:notice] = "Fetched #{new_count} new article(s)." if params[:trigger_fetch]
  end

  def show
    @rewrites       = @article.rewrites.where.not(llm_model: Article::ORIGINAL_REWRITE_MODEL)
                                        .includes(:ollama_server).order(created_at: :desc)
    @translations   = @article.translations.includes(:ollama_server).order(created_at: :desc)
    @ollama_servers = OllamaServer.enabled.order(:name)
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
      Task.enqueue_translate(rewrite, server:, model:, chain_autopost: false)
    end
    redirect_to admin_article_path(@article), notice: "#{targets.size} translation task(s) created."
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
end
