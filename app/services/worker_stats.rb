# Numbers for the worker status page (worker.khabarestan.com — see
# WorkerStatusController). `summary` is safe to show anyone: counts and
# health only, no error messages, hostnames or record contents. `details` is
# for signed-in users and adds errors, in-flight work and breakdowns.
module WorkerStats
  module_function

  RECENT_LIMIT = 15

  def summary(now: Time.current)
    pollers = BackgroundPollers::POLLERS.map do |poller|
      {
        name:             poller.name,
        interval_seconds: poller.interval.to_i,
        health:           BackgroundPollers.health(poller, now:),
        last_run_at:      BackgroundPollers.heartbeat(poller)&.dig(:last_run_at)
      }
    end

    oldest_pending_created_at = Task.pending.minimum(:created_at)

    {
      status:       pollers.all? { |poller_summary| poller_summary[:health] == :ok } ? :ok : :degraded,
      generated_at: now,
      pollers:,
      task_queue: {
        pending:                    Task.pending.count,
        claimed:                    Task.where(status: "claimed").count,
        completed_last_hour:        Task.where(status: "completed", completed_at: (now - 1.hour)..).count,
        completed_last_24_hours:    Task.where(status: "completed", completed_at: (now - 24.hours)..).count,
        failed_last_24_hours:       Task.where(status: "failed", updated_at: (now - 24.hours)..).count,
        oldest_pending_age_seconds: (oldest_pending_created_at && (now - oldest_pending_created_at).to_i)
      },
      publishing: {
        telegram_posts_queued:             TelegramPost.where(status: %w[pending sending]).count,
        telegram_posts_sent_last_24_hours: TelegramPost.where(status: "posted", posted_at: (now - 24.hours)..).count
      },
      ingestion: {
        articles_last_24_hours: Article.where(created_at: (now - 24.hours)..).count
      }
    }
  end

  def details(now: Time.current)
    open_task_counts = Task.where(status: %w[pending claimed]).group(:kind, :status).count

    {
      pollers: BackgroundPollers::POLLERS.map do |poller|
        { name: poller.name }.merge(BackgroundPollers.heartbeat(poller) || {})
      end,
      poller_process: BackgroundPollers.process_info,
      web_process: {
        hostname:      Socket.gethostname,
        role:          AppRole.current,
        ruby_version:  RUBY_VERSION,
        rails_version: Rails.version
      },
      open_tasks_by_kind: Task::KINDS.to_h do |kind|
        [ kind, { pending: open_task_counts.fetch([ kind, "pending" ], 0), claimed: open_task_counts.fetch([ kind, "claimed" ], 0) } ]
      end,
      pending_tasks_by_model: Task.pending.group(:model).count.sort_by { |_model, pending_count| -pending_count }.to_h,
      stale_claims:           Task.stale.count,
      in_flight_tasks:        Task.where(status: "claimed").includes(:ollama_server).order(:claimed_at).limit(RECENT_LIMIT).map { |task| task_row(task, now:) },
      recent_failed_tasks:    Task.where(status: "failed").includes(:ollama_server).order(updated_at: :desc).limit(RECENT_LIMIT).map { |task| task_row(task, now:) },
      telegram_post_errors:   TelegramPost.where(status: "error").includes(:telegram_channel).order(updated_at: :desc).limit(RECENT_LIMIT).map do |telegram_post|
        { id: telegram_post.id, channel: telegram_post.telegram_channel.name, error_message: telegram_post.error_message, updated_at: telegram_post.updated_at }
      end
    }
  end

  def task_row(task, now:)
    {
      id:            task.id,
      kind:          task.kind,
      model:         task.model,
      server:        task.ollama_server&.name,
      attempts:      task.attempts,
      claimed_at:    task.claimed_at,
      claimed_for_seconds: (task.claimed_at && (now - task.claimed_at).to_i),
      error_message: task.error_message,
      updated_at:    task.updated_at
    }
  end
end
