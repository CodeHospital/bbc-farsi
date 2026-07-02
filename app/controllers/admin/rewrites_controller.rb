class Admin::RewritesController < Admin::BaseController
  include Pagy::Method
  protect_from_forgery with: :null_session

  before_action :set_rewrite, only: %i[show edit update rerun activate archive]

  SORT_COLUMNS = {
    "article" => "articles.title",
    "model"   => "rewrites.llm_model",
    "status"  => "rewrites.status",
    "created" => "rewrites.created_at"
  }.freeze

  def index
    base = Rewrite.where(archived: params[:archived] == "1")
    @status_counts = base.group(:status).count

    rewrites = base.eager_load(:article) # LEFT JOIN: search/sort/show article without N+1
    rewrites = rewrites.where(status: params[:status])             if params[:status].present?
    rewrites = rewrites.where.not(articles: { status: "posted" }) if params[:hide_posted] == "1"
    if params[:q].present?
      like = "%#{params[:q]}%"
      rewrites = rewrites.where("LOWER(articles.title) LIKE LOWER(:q) OR LOWER(rewrites.content) LIKE LOWER(:q)", q: like)
    end

    @pagy, @rewrites = pagy(rewrites.order(sort_clause))
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

  # Re-queue a rewrite task for every selected rewrite, reusing each one's
  # own server/model — same as the single #rerun action.
  def bulk_rerun
    rewrite_ids = Array(params[:rewrite_ids]).reject(&:blank?)
    return redirect_back(fallback_location: admin_rewrites_path, alert: "Select at least one rewrite.") if rewrite_ids.empty?

    Rewrite.where(id: rewrite_ids).find_each do |rewrite|
      Task.enqueue_rewrite(rewrite.article, server: rewrite.ollama_server, model: rewrite.llm_model)
    end
    redirect_back fallback_location: admin_rewrites_path, notice: "Rerun queued for #{rewrite_ids.size} rewrite(s)."
  end

  def archive
    @rewrite.archive!
    redirect_to admin_article_path(@rewrite.article), notice: "Rewrite archived."
  end

  private

  def set_rewrite = @rewrite = Rewrite.find(params[:id])
  def rewrite_params = params.require(:rewrite).permit(:content)

  def sort_clause
    column    = SORT_COLUMNS[params[:sort]] || SORT_COLUMNS["created"]
    direction = params[:dir] == "asc" ? "asc" : "desc"
    order     = "#{column} #{direction}"
    order    += ", rewrites.created_at desc" unless column == SORT_COLUMNS["created"]
    Arel.sql(order)
  end
end
