# Status page for the background pollers and the LLM task queue, served on
# worker.khabarestan.com (or /worker when the app isn't split). Anyone sees the
# health summary; signed-in users (any admin/editor account) also get errors,
# in-flight tasks and breakdowns. JSON at status.json for uptime monitors.
class WorkerStatusController < ApplicationController
  layout "worker_status"

  def show
    @summary = WorkerStats.summary
    @details = WorkerStats.details if current_user

    respond_to do |format|
      format.html
      format.json { render json: @details ? @summary.merge(details: @details) : @summary }
    end
  end
end
