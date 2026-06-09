# Worker-facing task queue API.
#
#   GET  /api/tasks/next         -> claim the next pending task (or 204)
#   POST /api/tasks/:id/complete -> { responses: { key => content } }
#   POST /api/tasks/:id/fail     -> { error: "message" }
#
# All endpoints require the WORKER_API_TOKEN bearer token (see Api::BaseController).
class Api::TasksController < Api::BaseController
  # GET /api/tasks/next
  # Optional query param: models[] — list of model names the worker supports.
  # When provided, only tasks whose model is in the list are returned.
  def claim
    supported_models = Array(params[:models]).map(&:to_s).reject(&:empty?).presence
    task = Task.claim_next!(models: supported_models)
    return head :no_content unless task

    render json: task_payload(task)
  end

  # POST /api/tasks/:id/complete
  def complete
    task = Task.find(params[:id])
    task.complete!(responses_param)
    render json: { id: task.id, status: task.status }
  rescue StandardError => e
    task&.fail!(e.message)
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/tasks/:id/fail
  def mark_failed
    task = Task.find(params[:id])
    task.fail!(params[:error].to_s.presence || "worker reported failure")
    render json: { id: task.id, status: task.status }
  end

  private

  def task_payload(task)
    {
      id:         task.id,
      kind:       task.kind,
      model:      task.model,
      ollama_url: task.ollama_server&.url,
      requests:   task.requests
    }
  end

  def responses_param
    params.require(:responses).permit!.to_h
  end
end
