# Thin HTTP client for the llmarkt (vibeearning) LLM Grid API. See
# https://llmarkt.codehospital.com/api-docs for the full spec.
#
#   POST  {api_url}/jobs                Submit a job; llmarkt POSTs the result to
#                                        the `webhook_url` we supply when done
#                                        (handled by Api::LlmCallbacksController).
#   PATCH {api_url}/jobs/{id}/priority   Bump/lower a still-pending job's priority
#                                        by a signed delta.
#   POST  {api_url}/jobs/{id}/retry      Requeue a failed job in place (same job_id).
#
# Raises LlmarktClient::Error on any non-success response or transport failure so
# the caller can fall back to the Ollama worker / local-only behavior.
class LlmarktClient
  class Error < StandardError; end

  include HTTParty

  # Submit a single-prompt inference job. Returns the parsed response hash,
  # e.g. { "job_id" => "uuid", "status" => "pending", "created_at" => "..." }.
  def self.submit_job(model:, prompt:, webhook_url:, tag: nil, model_match: nil, priority: nil, timeout_seconds: nil)
    raise Error, "llmarkt is not configured" unless Llmarkt.enabled?

    body = {
      model:       model,
      prompt:      prompt,
      model_match: model_match || Llmarkt.model_match,
      webhook_url: webhook_url
    }
    body[:tag] = tag if tag.present?
    body[:priority] = priority if priority.present?
    body[:timeout_seconds] = timeout_seconds if timeout_seconds.present?

    response = post(
      "#{Llmarkt.api_url}/jobs",
      headers: auth_headers,
      body:    body.to_json,
      timeout: 15
    )

    parse_response(response, "POST /jobs")
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError => e
    raise Error, "llmarkt request error: #{e.class}: #{e.message}"
  end

  # Adjust a still-pending job's priority by a signed delta (positive raises it,
  # negative lowers it). Returns the parsed response, e.g. { "priority" => 10 }.
  # llmarkt 422s if the job is no longer pending or the delta is zero.
  def self.update_job_priority(job_id, delta)
    raise Error, "llmarkt is not configured" unless Llmarkt.enabled?

    response = patch(
      "#{Llmarkt.api_url}/jobs/#{job_id}/priority",
      headers: auth_headers,
      body:    { priority: delta }.to_json,
      timeout: 15
    )

    parse_response(response, "PATCH /jobs/#{job_id}/priority")
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError => e
    raise Error, "llmarkt request error: #{e.class}: #{e.message}"
  end

  # Requeue a failed job in place (clears the error/worker assignment, transitions
  # back to pending; job_id is unchanged). Returns the parsed Job. llmarkt 422s if
  # the job is not in the failed state.
  def self.retry_job(job_id)
    raise Error, "llmarkt is not configured" unless Llmarkt.enabled?

    response = post(
      "#{Llmarkt.api_url}/jobs/#{job_id}/retry",
      headers: auth_headers,
      timeout: 15
    )

    parse_response(response, "POST /jobs/#{job_id}/retry")
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError => e
    raise Error, "llmarkt request error: #{e.class}: #{e.message}"
  end

  def self.auth_headers
    { "Authorization" => "Bearer #{Llmarkt.api_key}", "Content-Type" => "application/json" }
  end
  private_class_method :auth_headers

  def self.parse_response(response, action)
    unless response.success?
      raise Error, "llmarkt #{action} failed (#{response.code}): #{response.body.to_s[0, 300]}"
    end

    parsed = response.parsed_response
    parsed.is_a?(String) ? JSON.parse(parsed) : parsed
  end
  private_class_method :parse_response
end
