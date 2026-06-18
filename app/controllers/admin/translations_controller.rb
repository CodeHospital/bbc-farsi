class Admin::TranslationsController < Admin::BaseController
  include Pagy::Method
  protect_from_forgery with: :null_session

  before_action :set_translation, only: %i[show edit update rerun activate refine post_to_channel archive]

  # Whitelisted sort keys -> SQL column expressions (guards against injection).
  SORT_COLUMNS = {
    "article" => "articles.title",
    "title"   => "translations.translated_title",
    "model"   => "translations.llm_model",
    "active"  => "translations.active",
    "status"  => "translations.status",
    "created" => "translations.created_at"
  }.freeze

  def index
    base = Translation.where(archived: params[:archived] == "1")
    @status_counts = base.group(:status).count
    @model_counts  = base.group(:llm_model).count
    @models        = @model_counts.keys.compact.sort

    translations = base.eager_load(:article) # LEFT JOIN: filter/sort on article columns
    translations = translations.where(status: params[:status])             if params[:status].present?
    translations = translations.where(llm_model: params[:model])           if params[:model].present?
    translations = translations.where(active: true)                        if params[:active] == "1"
    translations = translations.where.not(articles: { status: "posted" }) if params[:hide_posted] == "1"
    if params[:q].present?
      like = "%#{params[:q]}%"
      translations = translations.where("LOWER(articles.title) LIKE LOWER(:q) OR LOWER(translations.translated_title) LIKE LOWER(:q)", q: like)
    end

    @pagy, @translations = pagy(translations.order(sort_clause))
  end

  def show
    @telegram_channels  = TelegramChannel.enabled.order(:name)
    @posted_channel_ids = @translation.telegram_posts.where(status: "posted").pluck(:telegram_channel_id)
  end

  def edit; end

  def update
    if @translation.update(translation_params)
      redirect_to admin_translation_path(@translation), notice: "Translation saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def rerun
    Task.enqueue_translate(
      @translation.rewrite,
      server: @translation.ollama_server,
      model:  @translation.llm_model
    )
    redirect_to admin_article_path(@translation.article), notice: "Translation task re-created (#{@translation.llm_model})."
  end

  def activate
    @translation.activate!
    redirect_to admin_article_path(@translation.article), notice: "Translation ##{@translation.id} set as active."
  end

  def archive
    @translation.archive!
    redirect_to admin_article_path(@translation.article), notice: "Translation archived."
  end

  def refine
    server, model = OllamaServer.pick(:refine)
    return redirect_to(admin_article_path(@translation.article),
      alert: "No Ollama servers with refine models configured.") unless server

    Task.enqueue_refine(@translation, server:, model:)
    redirect_to admin_article_path(@translation.article),
      notice: "Refine task created (#{server.name} / #{model})."
  end

  def post_to_channel
    channel = TelegramChannel.find(params[:telegram_channel_id])
    post    = TelegramPost.find_or_initialize_by(translation: @translation, telegram_channel: channel)

    TelegramPoster.new.post(translation: @translation, channel:)
    post.update!(status: "posted", posted_at: Time.current)
    @translation.article.update!(status: "posted")

    redirect_back fallback_location: admin_translation_path(@translation),
                  notice: "Posted to #{channel.name}."
  rescue StandardError => e
    post&.update!(status: "error", error_message: e.message)
    redirect_back fallback_location: admin_translation_path(@translation),
                  alert: "Posting failed: #{e.message}"
  end

  private

  def set_translation = @translation = Translation.includes(:article, :rewrite, :ollama_server).find(params[:id])
  def translation_params = params.require(:translation).permit(:translated_title, :translated_body)

  # ORDER BY clause from whitelisted params, newest-first as a stable tiebreaker.
  def sort_clause
    column    = SORT_COLUMNS[params[:sort]] || SORT_COLUMNS["created"]
    direction = params[:dir] == "asc" ? "asc" : "desc"
    order     = "#{column} #{direction}"
    order += ", translations.created_at desc" unless column == SORT_COLUMNS["created"]
    Arel.sql(order)
  end
end
