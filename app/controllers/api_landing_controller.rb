# Public landing page for the API host: what this API is, how much it has
# processed, and its endpoints. Stats only (ApiStats); the endpoints themselves
# stay behind their own bearer / signed-token auth. Also available as JSON.
class ApiLandingController < ApplicationController
  layout "api_landing"

  ENDPOINTS = [
    { verb: "GET",  path: "/api/tasks/next",         auth: "worker bearer token",  purpose: "Worker claims the next pending task" },
    { verb: "POST", path: "/api/tasks/:id/complete", auth: "worker bearer token",  purpose: "Worker returns a task's results" },
    { verb: "POST", path: "/api/tasks/:id/fail",     auth: "worker bearer token",  purpose: "Worker reports a failed task" },
    { verb: "POST", path: "/api/llm_callbacks",      auth: "signed token",         purpose: "llmarkt delivers a finished job" },
    { verb: "POST", path: "/api/telegram_admin/webhook", auth: "Telegram secret header", purpose: "Admin-bot button taps" }
  ].freeze

  def show
    @stats = ApiStats.summary
    @endpoints = ENDPOINTS

    respond_to do |format|
      format.html
      format.json { render json: @stats }
    end
  end
end
