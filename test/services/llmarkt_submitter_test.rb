require "test_helper"

class LlmarktSubmitterTest < ActiveSupport::TestCase
  setup do
    stub_llmarkt_config

    @article = create_article
    @server  = OllamaServer.create!(
      name: "Local", url: "http://localhost:11434",
      rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b", refine_models: "qwen3:14b"
    )
  end

  teardown { restore_llmarkt_config }

  # ── build_prompt ────────────────────────────────────────────────────────────

  test "build_prompt flattens messages and substitutes placeholders" do
    request = {
      "key" => "title",
      "messages" => [
        { "role" => "system", "content" => "You are an editor." },
        { "role" => "user",   "content" => "Body was: {{body}}" }
      ]
    }
    prompt = LlmarktSubmitter.build_prompt(request, { "body" => "Hello world" })

    assert_equal "You are an editor.\n\nBody was: Hello world", prompt
  end

  # ── submit_task ──────────────────────────────────────────────────────────────

  test "submit_task returns false and leaves task pending when llmarkt disabled" do
    task = build_pending_rewrite_task

    with_llmarkt_disabled do
      assert_not LlmarktSubmitter.submit_task(task)
    end
    assert_equal "pending", task.reload.status
  end

  test "submit_task marks the task claimed and records the external job id" do
    task = build_pending_rewrite_task

    LlmarktClient.stub(:submit_job, ->(**) { { "job_id" => "job-abc" } }) do
      assert LlmarktSubmitter.submit_task(task)
    end

    task.reload
    assert_equal "claimed", task.status
    assert_equal "job-abc", task.external_job_id
    assert_equal "running", task.target.reload.status
  end

  # Exercises the real LlmarktClient.submit_job (only the HTTP layer is stubbed,
  # via WebMock, as in llmarkt_client_test.rb) rather than stubbing the method
  # itself — a `LlmarktClient.stub(:submit_job, ->(**) { ... })` double would
  # silently swallow a keyword-argument mismatch between this call site and the
  # real method signature (as happened when `priority:`/`timeout_seconds:` were
  # added here without updating LlmarktClient.submit_job to accept them).
  test "submit_task posts priority and timeout_seconds through the real submit_job signature" do
    task = build_pending_rewrite_task
    captured = nil
    stub_request(:post, "https://llmarkt.test/api/v1/jobs").to_return(
      status: 201, body: { job_id: "job-real" }.to_json, headers: { "Content-Type" => "application/json" }
    )

    assert LlmarktSubmitter.submit_task(task)

    assert_requested :post, "https://llmarkt.test/api/v1/jobs" do |req|
      captured = JSON.parse(req.body)
      true
    end
    assert_equal task.priority, captured["priority"]
    assert_equal 20.minutes.to_i, captured["timeout_seconds"]
    assert_equal "job-real", task.reload.external_job_id
  end

  test "submit_task rolls back to pending when submission raises" do
    task = build_pending_rewrite_task

    LlmarktClient.stub(:submit_job, ->(**) { raise LlmarktClient::Error, "boom" }) do
      assert_not LlmarktSubmitter.submit_task(task)
    end

    assert_equal "pending", task.reload.status
  end

  # ── handle_callback chaining ─────────────────────────────────────────────────

  test "handle_callback advances the chain then completes the task" do
    task = build_pending_rewrite_task

    LlmarktClient.stub(:submit_job, ->(**) { { "job_id" => "job-x" } }) do
      LlmarktSubmitter.submit_task(task) # submits request[0] ("body")

      assert_equal :continued, LlmarktSubmitter.handle_callback(task, "body", "Rewritten body text")
      assert_equal "Rewritten body text", task.reload.responses["body"]
      assert_equal "claimed", task.status

      assert_equal :completed, LlmarktSubmitter.handle_callback(task, "title", "New headline")
    end

    task.reload
    assert_equal "completed", task.status
    assert_equal "New headline", task.target.rewritten_title
    assert_equal "Rewritten body text", task.target.content
  end

  test "handle_callback ignores duplicate or out-of-order callbacks" do
    task = build_pending_rewrite_task

    LlmarktClient.stub(:submit_job, ->(**) { { "job_id" => "job-x" } }) do
      LlmarktSubmitter.submit_task(task)

      # "title" arrives before "body" — not the expected next key.
      assert_equal :ignored, LlmarktSubmitter.handle_callback(task, "title", "premature")
      assert_nil task.reload.responses&.dig("title")

      LlmarktSubmitter.handle_callback(task, "body", "the body")
      # duplicate "body" callback is ignored.
      assert_equal :ignored, LlmarktSubmitter.handle_callback(task, "body", "the body again")
      assert_equal "the body", task.reload.responses["body"]
    end
  end

  # ── update_priority ────────────────────────────────────────────────────────

  test "update_priority calls llmarkt when the task has an external job id" do
    task = build_pending_rewrite_task
    task.update_column(:external_job_id, "job-1")
    captured = nil

    LlmarktClient.stub(:update_job_priority, ->(job_id, delta) { captured = [ job_id, delta ]; { "priority" => 10 } }) do
      assert LlmarktSubmitter.update_priority(task, 10)
    end
    assert_equal [ "job-1", 10 ], captured
  end

  test "update_priority is a no-op without an external job id" do
    task = build_pending_rewrite_task

    LlmarktClient.stub(:update_job_priority, ->(*) { raise "should not be called" }) do
      assert_not LlmarktSubmitter.update_priority(task, 1)
    end
  end

  test "update_priority is a no-op for a zero delta" do
    task = build_pending_rewrite_task
    task.update_column(:external_job_id, "job-1")

    LlmarktClient.stub(:update_job_priority, ->(*) { raise "should not be called" }) do
      assert_not LlmarktSubmitter.update_priority(task, 0)
    end
  end

  test "update_priority swallows llmarkt errors and returns false" do
    task = build_pending_rewrite_task
    task.update_column(:external_job_id, "job-1")

    LlmarktClient.stub(:update_job_priority, ->(*) { raise LlmarktClient::Error, "not pending" }) do
      assert_not LlmarktSubmitter.update_priority(task, 1)
    end
  end

  # ── retry_task ─────────────────────────────────────────────────────────────

  test "retry_task calls llmarkt when the task has an external job id" do
    task = build_pending_rewrite_task
    task.update_column(:external_job_id, "job-1")
    captured = nil

    LlmarktClient.stub(:retry_job, ->(job_id) { captured = job_id; { "status" => "pending" } }) do
      assert LlmarktSubmitter.retry_task(task)
    end
    assert_equal "job-1", captured
  end

  test "retry_task is a no-op without an external job id" do
    task = build_pending_rewrite_task

    LlmarktClient.stub(:retry_job, ->(*) { raise "should not be called" }) do
      assert_not LlmarktSubmitter.retry_task(task)
    end
  end

  test "retry_task swallows llmarkt errors and returns false" do
    task = build_pending_rewrite_task
    task.update_column(:external_job_id, "job-1")

    LlmarktClient.stub(:retry_job, ->(*) { raise LlmarktClient::Error, "not failed" }) do
      assert_not LlmarktSubmitter.retry_task(task)
    end
  end

  private

  # Create a plain pending task without triggering the after_create_commit
  # auto-submit, so each test drives submission explicitly.
  def build_pending_rewrite_task
    with_llmarkt_disabled do
      Task.create!(
        kind: "rewrite", model: "qwen3:14b", ollama_server: @server,
        target: @article.rewrites.create!(llm_model: "qwen3:14b", status: "pending"),
        requests: ArticleRewriter.requests(@article), chain_translate: false
      )
    end
  end
end
