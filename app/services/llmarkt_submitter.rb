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
      timeout_seconds: Task::LLMARKT_JOB_TIMEOUT.to_i,
      priority:     task.priority,
      tag:         "task-#{task.target.article.feed.source}-#{key}"
    )

    task.update_columns(external_job_id: result["job_id"].to_s, updated_at: Time.current)
    Rails.logger.info("Llmarkt submitted task=#{task.id} key=#{key} job=#{result['job_id']}")
    result
  end

  # Handle a completed-job webhook for (task, key): record the output, then either
  # submit the next request in the chain or finish the task. Guards against
  # stale or duplicate callbacks by only acting on the next expected request
  # key, AND (C-4) by ignoring any callback whose job_id doesn't match the
  # task's current external_job_id — this is what makes a late webhook for a
  # job that was already stale-reclaimed (and so had its job_id cleared, or
  # replaced by a fresh submission) harmless instead of corrupting a task the
  # Ollama worker has since taken over. Runs under task.with_lock so a
  # concurrent duplicate delivery can't interleave with itself.
  def self.handle_callback(task, key, output, job_id: nil)
    task.with_lock do
      next :stale if stale_job?(task, job_id)

      responses = (task.responses || {}).dup

      expected_key = next_pending_key(task, responses)
      # Ignore duplicates (key already recorded) or out-of-order callbacks.
      next :ignored if responses.key?(key) || key != expected_key

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
  end

  # Handle a failed-job webhook: mark the task failed, unless the job_id no
  # longer matches (see handle_callback) — a late failure for a job we've
  # already moved on from must not clobber whatever the task is doing now.
  def self.handle_failure(task, job_id, message)
    task.with_lock do
      next :stale if stale_job?(task, job_id)

      task.fail!(message)
      :failed
    end
  end

  def self.stale_job?(task, job_id)
    job_id.present? && task.external_job_id.present? && task.external_job_id != job_id.to_s
  end

  # Best-effort mirror of a local priority change onto llmarkt's job (only
  # meaningful while the job is still queued there — llmarkt 422s otherwise,
  # which we treat the same as "nothing to sync"). Called from Task#reprioritize!
  # after the local `priority` column is already updated. Returns true on success.
  def self.update_priority(task, delta)
    return false unless Llmarkt.enabled?
    return false if task.external_job_id.blank? || delta.to_i.zero?

    LlmarktClient.update_job_priority(task.external_job_id, delta)
    true
  rescue StandardError => e
    Rails.logger.error("LlmarktSubmitter#update_priority task=#{task.id}: #{e.class}: #{e.message}")
    false
  end

  # Best-effort retry of a failed task's job on llmarkt, in place (same job_id).
  # Called from Task#retry!. Returns true on success; the caller falls back to
  # the plain local requeue (Ollama worker fallback) when this returns false.
  def self.retry_task(task)
    return false unless Llmarkt.enabled?
    return false if task.external_job_id.blank?

    LlmarktClient.retry_job(task.external_job_id)
    true
  rescue StandardError => e
    Rails.logger.error("LlmarktSubmitter#retry_task task=#{task.id}: #{e.class}: #{e.message}")
    false
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
