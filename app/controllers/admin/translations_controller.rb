class Admin::TranslationsController < Admin::BaseController
  include Pagy::Backend

  before_action :set_translation, only: %i[show edit update rerun activate refine post_to_channel archive]

  def index
    translations = Translation.includes(:article, :rewrite).order(created_at: :desc)
    translations = params[:archived] == "1" ? translations.where(archived: true) : translations.not_archived
    @pagy, @translations = pagy(translations)
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
    TranslateArticleJob.perform_later(
      @translation.rewrite_id,
      server_id: @translation.ollama_server_id,
      model:     @translation.llm_model
    )
    redirect_to admin_article_path(@translation.article), notice: "Translation re-queued (#{@translation.llm_model})."
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

    RefineTranslationJob.perform_later(@translation.id, server_id: server.id, model:)
    redirect_to admin_article_path(@translation.article),
      notice: "Refine job queued (#{server.name} / #{model})."
  end

  def post_to_channel
    channel = TelegramChannel.find(params[:telegram_channel_id])
    post    = TelegramPost.find_or_initialize_by(translation: @translation, telegram_channel: channel)

    TelegramPoster.new.post(translation: @translation, channel:)
    post.update!(status: "posted", posted_at: Time.current)
    @translation.article.update!(status: "posted")

    redirect_to admin_translation_path(@translation), notice: "Posted to #{channel.name}."
  rescue StandardError => e
    post&.update!(status: "error", error_message: e.message)
    redirect_to admin_translation_path(@translation), alert: "Posting failed: #{e.message}"
  end

  private

  def set_translation = @translation = Translation.includes(:article, :rewrite).find(params[:id])
  def translation_params = params.require(:translation).permit(:translated_title, :translated_body)
end
