# Admin-editable list of phrases that make feed ingestion skip an entry.
class Admin::SkipPhrasesController < Admin::BaseController
  before_action :require_admin!
  before_action :set_skip_phrase, only: %i[update destroy toggle]

  def index
    @skip_phrases = SkipPhrase.order(:match_field, :phrase)
    @new_skip_phrase = SkipPhrase.new(match_field: "title")
  end

  def create
    @new_skip_phrase = SkipPhrase.new(skip_phrase_params)
    if @new_skip_phrase.save
      redirect_to admin_skip_phrases_path, notice: "Skip phrase #{@new_skip_phrase.phrase.inspect} added."
    else
      @skip_phrases = SkipPhrase.order(:match_field, :phrase)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @skip_phrase.update(skip_phrase_params)
      redirect_to admin_skip_phrases_path, notice: "Skip phrase updated."
    else
      redirect_to admin_skip_phrases_path, alert: @skip_phrase.errors.full_messages.to_sentence
    end
  end

  def toggle
    @skip_phrase.update!(enabled: !@skip_phrase.enabled?)
    redirect_to admin_skip_phrases_path
  end

  def destroy
    @skip_phrase.destroy!
    redirect_to admin_skip_phrases_path, notice: "Skip phrase removed."
  end

  private

  def set_skip_phrase = @skip_phrase = SkipPhrase.find(params[:id])
  def skip_phrase_params = params.require(:skip_phrase).permit(:phrase, :match_field, :enabled)
end
