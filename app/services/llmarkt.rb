# Configuration + helpers for the llmarkt (vibeearning) LLM Grid integration.
#
# llmarkt is the PRIMARY LLM execution backend: when a Task is enqueued it is
# submitted to llmarkt over HTTP, and llmarkt calls back via a webhook when the
# job finishes (see LlmarktClient / LlmarktSubmitter / Api::LlmCallbacksController).
# The pull-based Ollama worker (worker/worker.rb) remains as a fallback for any
# task that could not be submitted (it stays `pending` and the worker claims it).
#
# Credentials are read from Rails credentials first, then ENV as a fallback:
#   credentials.llmarkt_api_url   / ENV["LLMARKT_API_URL"]    e.g. https://llmarkt.codehospital.com/api/v1
#   credentials.llmarkt_api_key   / ENV["LLMARKT_API_KEY"]    bearer token
#   credentials.app_base_url      / ENV["APP_BASE_URL"]       public URL of THIS app (for webhooks)
#   credentials.llmarkt_model_match / ENV["LLMARKT_MODEL_MATCH"]  "family" (default) or "exact"
module Llmarkt
  module_function

  # Full API base, including the version prefix, e.g.
  # "https://llmarkt.codehospital.com/api/v1". Trailing slash trimmed.
  def api_url
    fetch(:llmarkt_api_url, "LLMARKT_API_URL").to_s.chomp("/").presence
  end

  def api_key
    fetch(:llmarkt_api_key, "LLMARKT_API_KEY").presence
  end

  # Public base URL of this Rails app, used to build webhook callback URLs that
  # llmarkt can reach, e.g. "https://news.codehospital.com".
  def app_base_url
    fetch(:app_base_url, "APP_BASE_URL").to_s.chomp("/").presence
  end

  # "family" lets the grid route to any compatible variant of the model name;
  # "exact" requires the precise Ollama model name.
  def model_match
    fetch(:llmarkt_model_match, "LLMARKT_MODEL_MATCH").presence || "family"
  end

  # The integration is usable only when all three required values are present.
  # When false, submission is skipped and tasks fall through to the Ollama worker.
  def enabled?
    api_url.present? && api_key.present? && app_base_url.present?
  end

  # ── Signed webhook tokens ──────────────────────────────────────────────────
  # The callback URL carries a tamper-proof token encoding which task + request
  # key the result belongs to, so the public webhook needs no other auth and we
  # need no job-mapping table.
  def verifier
    Rails.application.message_verifier("llmarkt")
  end

  def sign(task_id:, key:)
    verifier.generate({ "task_id" => task_id, "key" => key })
  end

  # Returns the decoded hash, or raises ActiveSupport::MessageVerifier::InvalidSignature.
  def verify(token)
    verifier.verify(token.to_s)
  end

  # ── Incoming webhook signature (X-LLMOnDemand-Signature) ───────────────────
  # llmarkt signs every webhook with HMAC-SHA256 of the raw JSON body, keyed with
  # our API key, sent as "sha256=<hex>". Verify it (constant-time) before trusting
  # a callback. See Api::LlmCallbacksController.
  def webhook_signature(raw_body)
    "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", api_key.to_s, raw_body.to_s)
  end

  def valid_webhook_signature?(raw_body, provided_signature)
    return false if api_key.blank? || provided_signature.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      webhook_signature(raw_body), provided_signature.to_s
    )
  end

  def fetch(credential_key, env_key)
    Rails.application.credentials.dig(credential_key) || ENV[env_key]
  end
  private_class_method :fetch
end
