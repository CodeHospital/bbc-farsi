class Admin::RewritesController < Admin::BaseController
  include Pagy::Backend

  before_action :set_rewrite, only: %i[show edit update rerun activate archive]

  def index
    base = Rewrite.where(archived: params[:archived] == "1")
    @status_counts = base.group(:status).count

    rewrites = base.eager_load(:article) # LEFT JOIN: search/show article without N+1
    rewrites = rewrites.where(status: params[:status]) if params[:status].present?
    if params[:q].present?
      like = "%#{params[:q]}%"
      rewrites = rewrites.where("articles.title LIKE :q OR rewrites.content LIKE :q", q: like)
    end

    @pagy, @rewrites = pagy(rewrites.order(created_at: :desc))
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
    Task.enqueue_rewrite(
      @rewrite.article,
      server: @rewrite.ollama_server,
      model:  @rewrite.llm_model
    )
    redirect_to admin_article_path(@rewrite.article), notice: "Rewrite task re-created (#{@rewrite.llm_model})."
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
