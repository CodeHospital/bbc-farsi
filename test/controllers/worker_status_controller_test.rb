require "test_helper"

# Not split here, so the page lives at /worker on any host.
class WorkerStatusControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Heartbeats live in Rails.cache, a null store in tests.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "anyone sees poller health and queue counts, but no error details" do
    feed_poller, *other_pollers = BackgroundPollers::POLLERS
    BackgroundPollers.record_heartbeat(feed_poller, started_at: Time.current, sweep_error: RuntimeError.new("secret failure"))
    other_pollers.each { |poller| BackgroundPollers.record_heartbeat(poller, started_at: Time.current, sweep_error: nil) }
    Task.create!(kind: "rewrite", status: "pending", target: create_rewrite, model: "llama3")

    get worker_root_path
    assert_response :success
    assert_match "Degraded", response.body
    assert_match feed_poller.name, response.body
    assert_select ".badge.health-failing", count: 1
    assert_select ".badge.health-ok", count: other_pollers.size
    assert_no_match "secret failure", response.body
    assert_no_match "llama3", response.body
  end

  test "all pollers healthy reads as running" do
    BackgroundPollers::POLLERS.each { |poller| BackgroundPollers.record_heartbeat(poller, started_at: Time.current, sweep_error: nil) }

    get worker_root_path
    assert_match "All systems running", response.body
  end

  test "a poller that missed several intervals is stalled" do
    poller = BackgroundPollers::POLLERS.first
    BackgroundPollers.record_heartbeat(poller, started_at: 1.day.ago, sweep_error: nil)

    assert_equal :stalled, BackgroundPollers.health(poller)
    assert_equal :never_run, BackgroundPollers.health(BackgroundPollers::POLLERS.last)
  end

  test "signed-in users get errors, in-flight tasks and breakdowns" do
    BackgroundPollers.record_heartbeat(BackgroundPollers::POLLERS.first, started_at: Time.current,
                                       sweep_error: RuntimeError.new("feed host down"))
    in_flight_task = Task.create!(kind: "translate", status: "claimed", claimed_at: 2.minutes.ago,
                                  target: create_rewrite, model: "qwen3")
    log_in_as

    get worker_root_path
    assert_response :success
    assert_match "feed host down", response.body
    assert_match "qwen3", response.body
    assert_select "a[href=?]", admin_task_path(in_flight_task)
  end

  test "the JSON summary omits details unless signed in" do
    get worker_status_path(format: :json)
    assert_response :success
    status_json = response.parsed_body
    assert_equal %w[generated_at ingestion pollers publishing status task_queue], status_json.keys.sort
    assert_equal BackgroundPollers::POLLERS.size, status_json["pollers"].size

    log_in_as
    get worker_status_path(format: :json)
    assert response.parsed_body.key?("details")
  end

  test "worker sign-in rejects a wrong password and signs out" do
    user = create_admin_user
    post worker_login_path, params: { username: user.username, password: "nope" }
    assert_response :unprocessable_entity

    post worker_login_path, params: { username: user.username, password: TEST_USER_PASSWORD }
    assert_redirected_to worker_root_path

    delete worker_logout_path
    assert_redirected_to worker_root_path
    get worker_root_path
    assert_select "a[href=?]", worker_login_path
  end
end
