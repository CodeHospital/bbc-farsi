require "test_helper"

class Admin::HousekeepingControllerTest < ActionDispatch::IntegrationTest
  setup { log_in_as }

  test "requires login" do
    reset!
    get admin_housekeeping_path
    assert_redirected_to admin_login_path
  end

  test "editors are redirected away from housekeeping (admin-only)" do
    post admin_logout_path
    log_in_as(create_editor_user)

    get admin_housekeeping_path
    assert_redirected_to admin_root_path
  end

  test "show reports the pending task count" do
    create_task(kind: "rewrite")
    create_task(kind: "translate")

    get admin_housekeeping_path

    assert_response :success
    assert_select "a[href=?]", abort_pending_tasks_admin_housekeeping_path, count: 0 # it's a button_to form
    assert_match(/2\s+pending/, @response.body)
  end

  test "abort_pending_tasks fails pending tasks and stops their targets" do
    rewrite_task   = create_task(kind: "rewrite")
    translate_task = create_task(kind: "translate")

    post abort_pending_tasks_admin_housekeeping_path

    assert_redirected_to admin_housekeeping_path
    assert_equal "failed", rewrite_task.reload.status
    assert_equal "failed", translate_task.reload.status
    assert_equal Task::ABORT_MESSAGE, rewrite_task.error_message
    assert_equal "error", rewrite_task.target.reload.status
    assert_equal "error", translate_task.target.reload.status
  end

  test "abort_pending_tasks leaves claimed and completed tasks untouched" do
    pending_task = create_task(kind: "rewrite")
    claimed_task = create_task(kind: "translate", status: "claimed")

    post abort_pending_tasks_admin_housekeeping_path

    assert_equal "failed", pending_task.reload.status
    assert_equal "claimed", claimed_task.reload.status
  end

  test "abort_pending_tasks does not touch feature/tag anchor targets" do
    translation = create_translation(attrs: { status: "completed" })
    feature_task = Task.create!(kind: "feature", status: "pending", target: translation, model: "qwen3:14b")

    post abort_pending_tasks_admin_housekeeping_path

    assert_equal "failed", feature_task.reload.status
    assert_equal "completed", translation.reload.status # anchor untouched
  end

  private

  def create_task(kind:, status: "pending")
    target =
      case kind
      when "rewrite" then create_rewrite(attrs: { status: "pending" })
      else create_translation(attrs: { status: "pending" })
      end

    Task.create!(kind:, status:, target:, model: "qwen3:14b")
  end
end
