require "test_helper"

class Api::LlmCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_llmarkt_config

    article = create_article
    @task = with_llmarkt_disabled do
      Task.create!(
        kind: "rewrite", model: "qwen3:14b", status: "claimed", claimed_at: Time.current,
        target: article.rewrites.create!(llm_model: "qwen3:14b", status: "running"),
        requests: ArticleRewriter.requests(article), chain_translate: false
      )
    end
  end

  teardown { restore_llmarkt_config }

  test "completed callback with a valid signature + token records the output and advances" do
    token = Llmarkt.sign(task_id: @task.id, key: "body")
    body  = { token: token, status: "completed", output: "Body text" }.to_json

    LlmarktClient.stub(:submit_job, ->(**) { { "job_id" => "job-next" } }) do
      post_callback(body)
    end

    assert_response :ok
    assert_equal "Body text", @task.reload.responses["body"]
  end

  test "failed callback marks the task failed" do
    token = Llmarkt.sign(task_id: @task.id, key: "body")
    body  = { token: token, status: "failed", error: "grid error" }.to_json

    post_callback(body)

    assert_response :ok
    assert_equal "failed", @task.reload.status
    assert_equal "grid error", @task.error_message
  end

  test "a missing or invalid signature is rejected before any processing" do
    token = Llmarkt.sign(task_id: @task.id, key: "body")
    body  = { token: token, status: "completed", output: "Body text" }.to_json

    # No signature header at all.
    post "/api/llm_callbacks", params: body, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized

    # Wrong signature.
    post "/api/llm_callbacks", params: body,
                               headers: { "Content-Type" => "application/json", "X-LLMOnDemand-Signature" => "sha256=deadbeef" }
    assert_response :unauthorized

    # Signature computed over different bytes than the body.
    post "/api/llm_callbacks", params: body,
                               headers: { "Content-Type" => "application/json", "X-LLMOnDemand-Signature" => vibe_signature("{}") }
    assert_response :unauthorized

    assert_equal "claimed", @task.reload.status # untouched
  end

  test "the legacy X-Vibe-Signature header name is still accepted" do
    token = Llmarkt.sign(task_id: @task.id, key: "body")
    body  = { token: token, status: "failed", error: "grid error" }.to_json

    post "/api/llm_callbacks", params: body,
                               headers: { "Content-Type" => "application/json", "X-Vibe-Signature" => vibe_signature(body) }

    assert_response :ok
    assert_equal "failed", @task.reload.status
  end

  test "an invalid token (but valid signature) is rejected" do
    body = { token: "tampered", status: "completed", output: "x" }.to_json
    post_callback(body)

    assert_response :unauthorized
  end

  test "a valid token for a missing task returns not found" do
    token = Llmarkt.sign(task_id: 999_999, key: "body")
    body  = { token: token, status: "completed", output: "x" }.to_json
    post_callback(body)

    assert_response :not_found
  end

  private

  # POST a raw JSON body with a correct X-LLMOnDemand-Signature for it.
  def post_callback(body)
    post "/api/llm_callbacks", params: body,
                               headers: { "Content-Type" => "application/json", "X-LLMOnDemand-Signature" => vibe_signature(body) }
  end

  def vibe_signature(body)
    "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", Llmarkt.api_key, body)
  end
end
