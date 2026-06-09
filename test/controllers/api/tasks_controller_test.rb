require "test_helper"

class Api::TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["WORKER_API_TOKEN"] = "test-worker-token"
    @article = create_article
    @server  = OllamaServer.create!(name: "Local", url: "http://gpu.local:11434",
                                    rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b")
    @task    = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b", chain_translate: false)
  end

  def auth_headers(token = "test-worker-token")
    { "Authorization" => "Bearer #{token}" }
  end

  # ── Authentication ─────────────────────────────────────────────────────────

  test "rejects requests with no token" do
    get "/api/tasks/next"
    assert_response :unauthorized
  end

  test "rejects requests with a wrong token" do
    get "/api/tasks/next", headers: auth_headers("nope")
    assert_response :unauthorized
  end

  # ── Claim ──────────────────────────────────────────────────────────────────

  test "claim returns the next pending task with requests and the server url" do
    get "/api/tasks/next", headers: auth_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal @task.id, body["id"]
    assert_equal "rewrite", body["kind"]
    assert_equal "qwen3:14b", body["model"]
    assert_equal "http://gpu.local:11434", body["ollama_url"]
    assert_equal "content", body["requests"].first["key"]

    assert_equal "claimed", @task.reload.status
  end

  test "claim returns 204 when the queue is empty" do
    Task.claim_next! # drain the one task
    get "/api/tasks/next", headers: auth_headers
    assert_response :no_content
  end

  test "claim with matching models filter returns the task" do
    get "/api/tasks/next", params: { models: [ "qwen3:14b" ] }, headers: auth_headers
    assert_response :success
    assert_equal @task.id, JSON.parse(response.body)["id"]
  end

  test "claim with non-matching models filter returns 204" do
    get "/api/tasks/next", params: { models: [ "some-other-model:7b" ] }, headers: auth_headers
    assert_response :no_content
    assert_equal "pending", @task.reload.status
  end

  test "claim with empty models list claims any task" do
    get "/api/tasks/next", params: { models: [] }, headers: auth_headers
    assert_response :success
    assert_equal @task.id, JSON.parse(response.body)["id"]
  end

  # ── Complete ────────────────────────────────────────────────────────────────

  test "complete stores the result and marks the task completed" do
    Task.claim_next!

    post "/api/tasks/#{@task.id}/complete",
         params: { responses: { content: "The rewritten body." } },
         headers: auth_headers

    assert_response :success
    assert_equal "completed", @task.reload.status
    assert_equal "The rewritten body.", @task.target.reload.content
    assert_equal "rewritten", @article.reload.status
  end

  # ── Fail ────────────────────────────────────────────────────────────────────

  test "fail marks the task and target as errored" do
    Task.claim_next!

    post "/api/tasks/#{@task.id}/fail",
         params: { error: "Ollama unreachable" },
         headers: auth_headers

    assert_response :success
    assert_equal "failed", @task.reload.status
    assert_equal "error", @task.target.reload.status
  end

  test "unknown task id returns 404" do
    post "/api/tasks/999999/fail", params: { error: "x" }, headers: auth_headers
    assert_response :not_found
  end
end
