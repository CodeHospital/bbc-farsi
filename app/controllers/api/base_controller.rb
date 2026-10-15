# Base controller for the worker-facing API. Authenticated with a static bearer
# token (the `worker_api_token` credential, see AppCredentials). No cookies/CSRF — this is a machine-to-machine API.
class Api::BaseController < ActionController::API
  before_action :authenticate_worker!

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  def authenticate_worker!
    expected = AppCredentials.worker_api_token.to_s
    provided = request.headers["Authorization"].to_s.sub(/\ABearer\s+/i, "")

    return if expected.present? &&
              ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def not_found(exception)
    Sentry.capture_exception(exception)
    render json: { error: "not found" }, status: :not_found
  end
end
