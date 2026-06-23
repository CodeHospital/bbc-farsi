# Orchestrates running a Task's chat-request chain on llmarkt (vibeearning).
#
# A Task holds an ordered list of `requests`, each `{ "key" => ..., "messages" =>
# [{role, content}, ...] }`, where later requests may reference an earlier
# request's output via `{{key}}` placeholders (e.g. the rewrite "title" request
# references `{{body}}`). llmarkt jobs are single-prompt and asynchronous, so we
# run the chain ONE request at a time, advancing on each webhook callback:
#
#   submit_task -> submit request[0]
#     -> webhook(key0) -> record output -> submit request[1] (placeholders filled)
#       -> webhook(key1) -> record output -> ... -> task.complete!(responses)
#
# Each submitted job carries a signed webhook URL encoding (task_id, request key),
# so the callback knows exactly which task/step it belongs to with no DB mapping.
class LlmarktSubmitter
  # Submit the first request of a freshly-enqueued pending task. Returns true on
  # success. On any failure the task is left `pending` so the Ollama worker can
  # claim it as a fallback. No-op (returns false) when llmarkt is not configured.
  def self.submit_task(task)
    return false unless Llmarkt.enabled?
    return false if Array(task.requests).empty?

    claimed = task.with_lock do
      next false unless task.status == "pending"
      task.mark_claimed! # -> status "claimed", target running; worker won't pick it up
      true
    end
    return false unless claimed

    submit_request(task, 0)
    true
  rescue StandardError => e
    Rails.logger.error("LlmarktSubmitter#submit_task task=#{task.id}: #{e.class}: #{e.message}")
    # Roll back to pending so the worker fallback can run this task.
    begin
      task.requeue!
    rescue StandardError => rollback_error
      Rails.logger.error("LlmarktSubmitter rollback failed task=#{task.id}: #{rollback_error.message}")
    end
    false
  end

  # Build and submit the job for request[index], substituting any {{key}}
  # placeholders with outputs gathered so far, and record the returned job id.
  def self.submit_request(task, index)
    request = Array(task.requests)[index]
    raise ArgumentError, "no request at index #{index} for task #{task.id}" unless request

    key    = request["key"]
    prompt = build_prompt(request, task.responses || {})

    result = LlmarktClient.submit_job(
      model:       task.model,
      prompt:      prompt,
      webhook_url: callback_url(task, key),
      tag:         "task-#{task.id}-#{key}"
    )

    task.update_columns(external_job_id: result["job_id"].to_s, updated_at: Time.current)
    Rails.logger.info("Llmarkt submitted task=#{task.id} key=#{key} job=#{result['job_id']}")
    result
  end

  # Handle a completed-job webhook for (task, key): record the output, then either
  # submit the next request in the chain or finish the task. Guards against stale
  # or duplicate callbacks by only acting on the next expected request key.
  def self.handle_callback(task, key, output)
    responses = (task.responses || {}).dup

    expected_key = next_pending_key(task, responses)
    # Ignore duplicates (key already recorded) or out-of-order callbacks.
    return :ignored if responses.key?(key) || key != expected_key

    responses[key] = output.to_s
    task.update_column(:responses, responses)

    keys       = Array(task.requests).map { |r| r["key"] }
    next_index = keys.index(key).to_i + 1

    if next_index < keys.size
      submit_request(task, next_index)
      :continued
    else
      task.complete!(responses)
      :completed
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  # The first request key that has no recorded response yet — the one llmarkt
  # should currently be working on.
  def self.next_pending_key(task, responses)
    Array(task.requests).map { |r| r["key"] }.find { |k| !responses.key?(k) }
  end

  # Flatten a chat request (system + user messages) into a single prompt string,
  # filling {{key}} placeholders from earlier responses.
  def self.build_prompt(request, responses)
    Array(request["messages"]).map do |message|
      responses.reduce(message["content"].to_s) do |text, (placeholder_key, value)|
        text.gsub("{{#{placeholder_key}}}", value.to_s)
      end
    end.join("\n\n")
  end

  def self.callback_url(task, key)
    token = Llmarkt.sign(task_id: task.id, key: key)
    "#{Llmarkt.app_base_url}/api/llm_callbacks?token=#{CGI.escape(token)}"
  end
end
