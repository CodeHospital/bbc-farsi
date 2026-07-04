require "test_helper"

class LlmarktClientTest < ActiveSupport::TestCase
  setup    { stub_llmarkt_config(api_key: "secret-key") }
  teardown { restore_llmarkt_config }

  test "submit_job posts to /jobs with bearer auth and returns the parsed body" do
    stub = stub_request(:post, "https://llmarkt.test/api/v1/jobs")
           .with(
             headers: { "Authorization" => "Bearer secret-key", "Content-Type" => "application/json" }
           )
           .to_return(
             status:  201,
             body:    { job_id: "job-1", status: "pending" }.to_json,
             headers: { "Content-Type" => "application/json" }
           )

    result = LlmarktClient.submit_job(
      model: "llama3", prompt: "hello", webhook_url: "https://app.test/api/llm_callbacks?token=x"
    )

    assert_equal "job-1", result["job_id"]
    assert_requested stub
  end

  test "submit_job sends model, prompt, model_match and webhook_url in the body" do
    captured = nil
    stub_request(:post, "https://llmarkt.test/api/v1/jobs").to_return(
      status: 201, body: { job_id: "j" }.to_json, headers: { "Content-Type" => "application/json" }
    )

    LlmarktClient.submit_job(
      model: "mistral", prompt: "translate this", webhook_url: "https://app.test/cb", tag: "task-7-body"
    )

    assert_requested :post, "https://llmarkt.test/api/v1/jobs" do |req|
      captured = JSON.parse(req.body)
      true
    end
    assert_equal "mistral", captured["model"]
    assert_equal "translate this", captured["prompt"]
    assert_equal "family", captured["model_match"]
    assert_equal "task-7-body", captured["tag"]
    assert_equal "https://app.test/cb", captured["webhook_url"]
  end

  test "submit_job forwards priority and timeout_seconds when given" do
    captured = nil
    stub_request(:post, "https://llmarkt.test/api/v1/jobs").to_return(
      status: 201, body: { job_id: "j" }.to_json, headers: { "Content-Type" => "application/json" }
    )

    LlmarktClient.submit_job(
      model: "mistral", prompt: "translate this", webhook_url: "https://app.test/cb",
      priority: 2, timeout_seconds: 1200
    )

    assert_requested :post, "https://llmarkt.test/api/v1/jobs" do |req|
      captured = JSON.parse(req.body)
      true
    end
    assert_equal 2, captured["priority"]
    assert_equal 1200, captured["timeout_seconds"]
  end

  test "submit_job omits priority and timeout_seconds when not given" do
    captured = nil
    stub_request(:post, "https://llmarkt.test/api/v1/jobs").to_return(
      status: 201, body: { job_id: "j" }.to_json, headers: { "Content-Type" => "application/json" }
    )

    LlmarktClient.submit_job(model: "mistral", prompt: "translate this", webhook_url: "https://app.test/cb")

    assert_requested :post, "https://llmarkt.test/api/v1/jobs" do |req|
      captured = JSON.parse(req.body)
      true
    end
    assert_not captured.key?("priority")
    assert_not captured.key?("timeout_seconds")
  end

  test "submit_job raises on a non-success response" do
    stub_request(:post, "https://llmarkt.test/api/v1/jobs").to_return(
      status: 422, body: { error: "unsupported model" }.to_json
    )

    error = assert_raises(LlmarktClient::Error) do
      LlmarktClient.submit_job(model: "nope", prompt: "x", webhook_url: "https://app.test/cb")
    end
    assert_match(/422/, error.message)
  end

  test "submit_job raises when llmarkt is not configured" do
    with_llmarkt_disabled do
      assert_raises(LlmarktClient::Error) do
        LlmarktClient.submit_job(model: "llama3", prompt: "x", webhook_url: "https://app.test/cb")
      end
    end
  end

  # ── update_job_priority ─────────────────────────────────────────────────────

  test "update_job_priority patches /jobs/:id/priority with the signed delta" do
    captured = nil
    stub_request(:patch, "https://llmarkt.test/api/v1/jobs/job-1/priority")
      .with(headers: { "Authorization" => "Bearer secret-key" })
      .to_return(status: 200, body: { priority: 10 }.to_json, headers: { "Content-Type" => "application/json" })

    result = LlmarktClient.update_job_priority("job-1", 10)

    assert_equal 10, result["priority"]
    assert_requested :patch, "https://llmarkt.test/api/v1/jobs/job-1/priority" do |req|
      captured = JSON.parse(req.body)
      true
    end
    assert_equal 10, captured["priority"]
  end

  test "update_job_priority raises on a non-success response" do
    stub_request(:patch, "https://llmarkt.test/api/v1/jobs/job-1/priority")
      .to_return(status: 422, body: { error: "job not pending" }.to_json)

    error = assert_raises(LlmarktClient::Error) { LlmarktClient.update_job_priority("job-1", -5) }
    assert_match(/422/, error.message)
  end

  test "update_job_priority raises when llmarkt is not configured" do
    with_llmarkt_disabled do
      assert_raises(LlmarktClient::Error) { LlmarktClient.update_job_priority("job-1", 5) }
    end
  end

  # ── retry_job ────────────────────────────────────────────────────────────────

  test "retry_job posts to /jobs/:id/retry and returns the requeued job" do
    stub_request(:post, "https://llmarkt.test/api/v1/jobs/job-1/retry")
      .with(headers: { "Authorization" => "Bearer secret-key" })
      .to_return(status: 200, body: { job_id: "job-1", status: "pending" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    result = LlmarktClient.retry_job("job-1")

    assert_equal "pending", result["status"]
  end

  test "retry_job raises on a non-success response" do
    stub_request(:post, "https://llmarkt.test/api/v1/jobs/job-1/retry")
      .to_return(status: 422, body: { error: "job not failed" }.to_json)

    error = assert_raises(LlmarktClient::Error) { LlmarktClient.retry_job("job-1") }
    assert_match(/422/, error.message)
  end

  test "retry_job raises when llmarkt is not configured" do
    with_llmarkt_disabled do
      assert_raises(LlmarktClient::Error) { LlmarktClient.retry_job("job-1") }
    end
  end
end
