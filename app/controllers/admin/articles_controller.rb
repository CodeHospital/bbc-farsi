class Admin::ArticlesController < Admin::BaseController
  include Pagy::Backend

  before_action :set_article, only: %i[show rewrite multi_rewrite translate multi_translate archive unarchive]

  def index
    FetchFeedsJob.perform_later if params[:trigger_fetch]
    articles = Article.includes(:feed).order(created_at: :desc)
    articles = params[:archived] == "1" ? articles.where(archived: true) : articles.not_archived
    articles = articles.where(status: params[:status])   if params[:status].present?
    articles = articles.where(feed_id: params[:feed_id]) if params[:feed_id].present?
    @pagy, @articles = pagy(articles)
    @feeds = Feed.order(:name)
    flash.now[:notice] = "Feed fetch queued." if params[:trigger_fetch]
  end

  def show
    @rewrites       = @article.rewrites.includes(:ollama_server).order(created_at: :desc)
    @translations   = @article.translations.includes(:ollama_server).order(created_at: :desc)
    @ollama_servers = OllamaServer.enabled.order(:name)
  end

  def rewrite
    server, model = OllamaServer.pick(:rewrite)
    return redirect_to(admin_article_path(@article), alert: "No Ollama servers with rewrite models configured.") unless server
    RewriteArticleJob.perform_later(@article.id, server_id: server.id, model:)
    redirect_to admin_article_path(@article), notice: "Rewrite queued (#{server.name} / #{model})."
  end

  def multi_rewrite
    targets = Array(params[:targets]).reject(&:blank?)
    return redirect_to(admin_article_path(@article), alert: "Select at least one target.") if targets.empty?

    targets.each do |target|
      server_id_str, model = target.split("|", 2)
      server_id = server_id_str.to_i
      RewriteArticleJob.perform_later(@article.id, server_id:, model:, chain_translate: false)
    end
    redirect_to admin_article_path(@article), notice: "#{targets.size} rewrite job(s) queued."
  end

  def translate
    rewrite = @article.rewrites.completed.last
    return redirect_to(admin_article_path(@article), alert: "No completed rewrite found.") unless rewrite

    server, model = OllamaServer.pick(:translate)
    return redirect_to(admin_article_path(@article), alert: "No Ollama servers with translate models configured.") unless server

    TranslateArticleJob.perform_later(rewrite.id, server_id: server.id, model:)
    redirect_to admin_article_path(@article), notice: "Translation queued (#{server.name} / #{model})."
  end

  def multi_translate
    targets    = Array(params[:targets]).reject(&:blank?)
    rewrite_id = params[:rewrite_id].presence
    return redirect_to(admin_article_path(@article), alert: "Select at least one target.") if targets.empty?

    rewrite = rewrite_id ? @article.rewrites.find_by(id: rewrite_id) : @article.rewrites.completed.last
    return redirect_to(admin_article_path(@article), alert: "No completed rewrite found.") unless rewrite

    targets.each do |target|
      server_id_str, model = target.split("|", 2)
      server_id = server_id_str.to_i
      TranslateArticleJob.perform_later(rewrite.id, server_id:, model:, chain_autopost: false)
    end
    redirect_to admin_article_path(@article), notice: "#{targets.size} translation job(s) queued."
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
