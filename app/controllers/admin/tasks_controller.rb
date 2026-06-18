class Admin::TasksController < Admin::BaseController
  include Pagy::Method

  before_action :set_task, only: %i[show retry cancel prioritize]

  SORT_COLUMNS = {
    "priority" => "tasks.priority",
    "kind"     => "tasks.kind",
    "status"   => "tasks.status",
    "attempts" => "tasks.attempts",
    "created"  => "tasks.created_at"
  }.freeze

  def index
    tasks = Task.includes(:target, :ollama_server).order(sort_clause)
    tasks = tasks.where(status: params[:status]) if params[:status].present?
    tasks = tasks.where(kind: params[:kind])     if params[:kind].present?
    tasks = filter_by_article_text(tasks, params[:q]) if params[:q].present?

    @counts = Task.group(:status).count
    @kind_counts = Task.group(:kind).count
    # Cross-filtered counts: status counts within the selected kind, and kind
    # counts within the selected status. Nil when that filter isn't active, so
    # the badges fall back to plain totals.
    @status_counts_in_kind = Task.where(kind: params[:kind]).group(:status).count if params[:kind].present?
    @kind_counts_in_status = Task.where(status: params[:status]).group(:kind).count if params[:status].present?

    @pagy, @tasks = pagy(tasks)
  end

  def show; end

  def retry
    @task.requeue!
    redirect_to admin_tasks_path, notice: "Task ##{@task.id} re-queued."
  end

  def cancel
    if @task.status == "pending"
      @task.fail!("Cancelled by admin")
      redirect_back fallback_location: admin_tasks_path, notice: "Task ##{@task.id} cancelled."
    else
      redirect_back fallback_location: admin_tasks_path, alert: "Only pending tasks can be cancelled."
    end
  end

  def prioritize
    @task.reprioritize!(params[:direction])
    redirect_back fallback_location: admin_tasks_path,
                  notice: "Task ##{@task.id} priority is now #{@task.priority}."
  end

  # Change priority for many tasks at once. Either step every selected task
  # up/down (`direction`) or set them all to an exact value (`priority`).
  def bulk_prioritize
    task_ids = Array(params[:task_ids]).reject(&:blank?)
    return redirect_back(fallback_location: admin_tasks_path, alert: "Select at least one task.") if task_ids.empty?

    scope = Task.where(id: task_ids)
    if params[:direction].present?
      step = params[:direction] == "down" ? -1 : 1
      scope.update_all("priority = priority + #{step}")
      notice = "#{step.positive? ? 'Raised' : 'Lowered'} priority of #{task_ids.size} task(s)."
    elsif params[:priority].present?
      scope.update_all(priority: params[:priority].to_i)
      notice = "Set priority of #{task_ids.size} task(s) to #{params[:priority].to_i}."
    else
      return redirect_back(fallback_location: admin_tasks_path, alert: "Choose a bulk priority action.")
    end

    redirect_back fallback_location: admin_tasks_path, notice:
  end

  private

  def set_task = @task = Task.includes(:target, :ollama_server).find(params[:id])

  # Default: priority DESC (highest first), tiebroken by newest.
  # Any explicit sort param overrides, with priority as a secondary tiebreaker.
  def sort_clause
    column    = SORT_COLUMNS[params[:sort]]
    direction = params[:dir] == "asc" ? "asc" : "desc"
    if column.nil?
      Arel.sql("tasks.created_at desc")
    elsif column == SORT_COLUMNS["priority"]
      Arel.sql("tasks.priority #{direction}, tasks.created_at desc")
    else
      Arel.sql("#{column} #{direction}, tasks.priority desc")
    end
  end

  # Filter tasks whose target's article matches the free-text query. `target` is
  # polymorphic (Rewrite or Translation), so resolve matching article ids first,
  # then the rewrite/translation ids that point at them.
  def filter_by_article_text(tasks, query)
    article_ids     = Article.where("LOWER(title) LIKE LOWER(:q) OR LOWER(description) LIKE LOWER(:q)", q: "%#{query}%").pluck(:id)
    rewrite_ids     = Rewrite.where(article_id: article_ids).pluck(:id)
    translation_ids = Translation.where(article_id: article_ids).pluck(:id)

    tasks.where(
      "(tasks.target_type = 'Rewrite'     AND tasks.target_id IN (:rewrites)) OR " \
      "(tasks.target_type = 'Translation' AND tasks.target_id IN (:translations))",
      rewrites: rewrite_ids, translations: translation_ids
    )
  end
end
