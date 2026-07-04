# Admin maintenance actions (queue cleanup, etc.).
class Admin::HousekeepingController < Admin::BaseController
  before_action :require_admin!

  def show
    @pending_task_count = Task.pending.count
  end

  # Cancel every queued (pending) task. See Task.abort_pending!.
  def abort_pending_tasks
    count = Task.abort_pending!
    notice = count.zero? ? "No pending tasks to abort." : "Aborted #{count} pending task(s)."
    redirect_to admin_housekeeping_path, notice:
  end
end
