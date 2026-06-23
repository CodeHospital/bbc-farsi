# Thin HTTP client for the llmarkt (vibeearning) LLM Grid API.
#
# Only the endpoint we need is implemented: submitting an inference job. llmarkt
# returns immediately with a pending job and later POSTs the completed result to
# the `webhook_url` we supply (handled by Api::LlmCallbacksController).
#
#   POST {api_url}/jobs
#   Authorization: Bearer {api_key}
#   { "model": "...", "prompt": "...", "model_match": "family",
#     "tag": "...", "webhook_url": "https://.../api/llm_callbacks?token=..." }
#
# Raises LlmarktClient::Error on any non-success response or transport failure so
# the caller can fall back to the Ollama worker.
class LlmarktClient
  class Error < StandardError; end

  include HTTParty

  # Submit a single-prompt inference job. Returns the parsed response hash,
  # e.g. { "job_id" => "uuid", "status" => "pending", "created_at" => "..." }.
  def self.submit_job(model:, prompt:, webhook_url:, tag: nil, model_match: nil)
    raise Error, "llmarkt is not configured" unless Llmarkt.enabled?

    body = {
      model:       model,
      prompt:      prompt,
      model_match: model_match || Llmarkt.model_match,
      webhook_url: webhook_url
    }
    body[:tag] = tag if tag.present?

    response = post(
      "#{Llmarkt.api_url}/jobs",
      headers: {
        "Authorization" => "Bearer #{Llmarkt.api_key}",
        "Content-Type"  => "application/json"
      },
      body:    body.to_json,
      timeout: 15
    )

    unless response.success?
      raise Error, "llmarkt POST /jobs failed (#{response.code}): #{response.body.to_s[0, 300]}"
    end

    parsed = response.parsed_response
    parsed = JSON.parse(parsed) if parsed.is_a?(String)
    parsed
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError => e
    raise Error, "llmarkt request error: #{e.class}: #{e.message}"
  end
end
