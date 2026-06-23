# Public webhook endpoint that llmarkt (vibeearning) calls when an inference job
# finishes. It is authenticated two ways, both required:
#
#   1. X-Vibe-Signature — HMAC-SHA256 of the raw body keyed with our API key, so
#      we know the request genuinely came from llmarkt (verified constant-time).
#   2. A signed token in the URL encoding which Task + request key the result is
#      for, so we know where to route it (and that WE issued this callback URL).
#
#   POST /api/llm_callbacks?token=<signed task_id+key>
#   X-Vibe-Signature: sha256=<hmac>
#   body: same payload as GET /v1/jobs/:id, e.g.
#     { "job_id": "...", "status": "completed", "output": "...", ... }
#
# On a completed job we record the output and advance the chain (or complete the
# task); on a failed job we mark the task failed.
class Api::LlmCallbacksController < ActionController::API
  class InvalidSignature < StandardError; end

  def create
    verify_webhook_signature!

    payload = Llmarkt.verify(params[:token])
    task    = Task.find(payload["task_id"])
    key     = payload["key"]

    case params[:status].to_s
    when "failed"
      task.fail!(params[:error].to_s.presence || "llmarkt job failed")
    when "completed"
      LlmarktSubmitter.handle_callback(task, key, params[:output])
    else
      # Non-terminal status (pending/claimed/running) — nothing to do yet.
      Rails.logger.info("llmarkt callback ignored (status=#{params[:status]}) task=#{task.id} key=#{key}")
    end

    head :ok
  rescue InvalidSignature, ActiveSupport::MessageVerifier::InvalidSignature
    head :unauthorized
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue StandardError => e
    Rails.logger.error("llmarkt callback error: #{e.class}: #{e.message}")
    head :unprocessable_entity
  end

  private

  def verify_webhook_signature!
    provided = request.headers["X-Vibe-Signature"]
    return if Llmarkt.valid_webhook_signature?(request.raw_post, provided)

    raise InvalidSignature, "X-Vibe-Signature verification failed"
  end
end
