class Admin::RewritesController < Admin::BaseController
  include Pagy::Backend

  before_action :set_rewrite, only: %i[show edit update rerun activate archive]

  def index
    rewrites = Rewrite.includes(:article).order(created_at: :desc)
    rewrites = params[:archived] == "1" ? rewrites.where(archived: true) : rewrites.not_archived
    @pagy, @rewrites = pagy(rewrites)
  end

  def show; end

  def edit; end

  def update
    if @rewrite.update(rewrite_params)
      redirect_to admin_rewrite_path(@rewrite), notice: "Rewrite saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def rerun
    RewriteArticleJob.perform_later(
      @rewrite.article_id,
      server_id: @rewrite.ollama_server_id,
      model:     @rewrite.llm_model
    )
    redirect_to admin_article_path(@rewrite.article), notice: "Rewrite re-queued (#{@rewrite.llm_model})."
  end

  def activate
    @rewrite.activate!
    redirect_to admin_article_path(@rewrite.article), notice: "Rewrite ##{@rewrite.id} set as active."
  end

  def archive
    @rewrite.archive!
    redirect_to admin_article_path(@rewrite.article), notice: "Rewrite archived."
  end

  private

  def set_rewrite = @rewrite = Rewrite.find(params[:id])
  def rewrite_params = params.require(:rewrite).permit(:content)
end
