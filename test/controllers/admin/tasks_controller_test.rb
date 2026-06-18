require "test_helper"

class Admin::TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
    log_in
  end

  test "lists tasks" do
    create_task(kind: "rewrite")
    get admin_tasks_path
    assert_response :success
  end

  test "filters by kind" do
    rewrite_task   = create_task(kind: "rewrite")
    translate_task = create_task(kind: "translate")

    get admin_tasks_path(kind: "rewrite")
    assert_response :success
    assert_select "a[href=?]", admin_task_path(rewrite_task)
    assert_select "a[href=?]", admin_task_path(translate_task), count: 0
  end

  test "an active filter toggles off (links back to the cleared list)" do
    create_task(kind: "rewrite", status: "failed")

    get admin_tasks_path(status: "failed", kind: "rewrite")
    assert_response :success
    # The active Failed status button points back to the list with status cleared
    # (kind preserved); the active Rewrite kind button clears kind (status kept).
    assert_select "a[aria-pressed=true][href=?]", admin_tasks_path(kind: "rewrite")
    assert_select "a[aria-pressed=true][href=?]", admin_tasks_path(status: "failed")
    # An inactive button still sets its value.
    assert_select "a[aria-pressed=false][href=?]", admin_tasks_path(status: "pending", kind: "rewrite")
  end

  test "combines kind and status filters" do
    keep = create_task(kind: "rewrite", status: "failed")
    create_task(kind: "rewrite", status: "completed") # wrong status
    create_task(kind: "translate", status: "failed")  # wrong kind

    get admin_tasks_path(kind: "rewrite", status: "failed")
    assert_response :success
    assert_select "a[href=?]", admin_task_path(keep)
    assert_select "tbody tr", count: 1
  end

  test "status badges show filtered/total when a kind is selected" do
    create_task(kind: "rewrite", status: "failed")
    create_task(kind: "translate", status: "failed")

    # No kind selected: plain totals.
    get admin_tasks_path
    assert_select ".badge.badge-status-failed", text: "2"

    # Kind selected: failed badge shows "<failed-in-kind>/<failed-total>".
    get admin_tasks_path(kind: "rewrite")
    assert_select ".badge.badge-status-failed", text: "1/2"
  end

  test "kind badges show filtered/total when a status is selected" do
    create_task(kind: "rewrite", status: "failed")
    create_task(kind: "rewrite", status: "completed")

    get admin_tasks_path(status: "failed")
    # rewrite kind: 1 failed of 2 total rewrites.
    assert_select ".badge.bg-secondary", text: "1/2"
  end

  test "search matches both rewrite and translation tasks by article text" do
    article     = create_article(attrs: { title: "Mars rover discovery" })
    rewrite     = create_rewrite(article: article)
    translation = create_translation(rewrite: rewrite) # same article
    rewrite_task   = Task.create!(kind: "rewrite",   status: "pending", model: "m", target: rewrite)
    translate_task = Task.create!(kind: "translate", status: "pending", model: "m", target: translation)
    other_task     = create_task(kind: "rewrite") # default "Test article title"

    get admin_tasks_path(q: "Mars")
    assert_response :success
    assert_select "a[href=?]", admin_task_path(rewrite_task)
    assert_select "a[href=?]", admin_task_path(translate_task)
    assert_select "a[href=?]", admin_task_path(other_task), count: 0
  end

  test "search composes with the kind filter" do
    article = create_article(attrs: { title: "Eclipse season" })
    kept    = Task.create!(kind: "rewrite",   status: "pending", model: "m", target: create_rewrite(article: article))
    Task.create!(kind: "translate", status: "pending", model: "m", target: create_translation(rewrite: create_rewrite(article: article)))

    get admin_tasks_path(q: "Eclipse", kind: "rewrite")
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "a[href=?]", admin_task_path(kept)
  end

  test "bulk_prioritize raises priority for only the selected tasks" do
    selected   = create_task(kind: "rewrite", status: "pending")
    also        = create_task(kind: "rewrite", status: "pending")
    untouched  = create_task(kind: "rewrite", status: "pending")

    patch bulk_prioritize_admin_tasks_path, params: { task_ids: [ selected.id, also.id ], direction: "up" }
    assert_response :redirect
    assert_equal 1, selected.reload.priority
    assert_equal 1, also.reload.priority
    assert_equal 0, untouched.reload.priority
  end

  test "bulk_prioritize sets an exact priority" do
    one = create_task(kind: "rewrite", status: "pending")
    two = create_task(kind: "rewrite", status: "pending")

    patch bulk_prioritize_admin_tasks_path, params: { task_ids: [ one.id, two.id ], priority: "5" }
    assert_equal 5, one.reload.priority
    assert_equal 5, two.reload.priority
  end

  test "bulk_prioritize with no selection redirects with an alert" do
    patch bulk_prioritize_admin_tasks_path, params: { task_ids: [], direction: "up" }
    assert_response :redirect
    follow_redirect!
    assert_select ".alert-danger"
  end

  test "prioritize raises and lowers a task's priority" do
    task = create_task(kind: "rewrite", status: "pending")

    patch prioritize_admin_task_path(task), params: { direction: "up" }
    assert_response :redirect
    assert_equal 1, task.reload.priority

    patch prioritize_admin_task_path(task), params: { direction: "down" }
    patch prioritize_admin_task_path(task), params: { direction: "down" }
    assert_equal(-1, task.reload.priority)
  end

  test "index shows priority controls for a pending task" do
    task = create_task(kind: "rewrite", status: "pending")
    get admin_tasks_path
    assert_response :success
    assert_select "form[action=?]", prioritize_admin_task_path(task)
  end

  test "paginates and preserves the active filter in page links" do
    30.times { create_task(kind: "rewrite", status: "failed") }

    get admin_tasks_path(kind: "rewrite", status: "failed")
    assert_response :success
    # Numbered page link to page 2 carries both filters forward.
    assert_select "ul.pagination a[href=?]",
                  admin_tasks_path(kind: "rewrite", status: "failed", page: 2)
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end

  def create_task(kind:, status: "pending")
    target =
      case kind
      when "rewrite" then create_rewrite(attrs: { status: "pending" })
      else create_translation(attrs: { status: "pending" })
      end

    Task.create!(kind:, status:, target:, model: "qwen3:14b")
  end
end
