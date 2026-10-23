# Public numbers about the work processed through the API, for the landing page
# on api.khabarestan.com (ApiLandingController). Aggregates only: no task
# contents, models, servers, errors or hostnames. Cached briefly because the
# page is public.
module ApiStats
  module_function

  CACHE_KEY    = "api_stats/v1".freeze
  CACHE_FOR    = 30.seconds
  DAYS_SHOWN   = 7
  DURATION_SAMPLE_LIMIT = 5_000

  def summary(now: Time.current)
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_FOR) { compute(now) }
  end

  def compute(now)
    completed_last_24_hours = Task.where(status: "completed", completed_at: (now - 24.hours)..).count
    failed_last_24_hours    = Task.where(status: "failed", updated_at: (now - 24.hours)..).count
    finished_last_24_hours  = completed_last_24_hours + failed_last_24_hours

    {
      generated_at: now,
      processed: {
        total:                   Task.where(status: "completed").count,
        last_hour:               Task.where(status: "completed", completed_at: (now - 1.hour)..).count,
        last_24_hours:           completed_last_24_hours,
        last_7_days:             Task.where(status: "completed", completed_at: (now - 7.days)..).count,
        failed_last_24_hours:    failed_last_24_hours,
        success_rate_last_24_hours_percent: (finished_last_24_hours.zero? ? nil : (completed_last_24_hours * 100.0 / finished_last_24_hours).round(1))
      },
      queue: {
        pending:  Task.pending.count,
        in_flight: Task.where(status: "claimed").count
      },
      average_processing_seconds_last_24_hours: average_processing_seconds(now),
      completed_by_kind_last_24_hours: Task::KINDS.to_h do |kind|
        [ kind, Task.where(kind:, status: "completed", completed_at: (now - 24.hours)..).count ]
      end,
      completed_per_day: completed_per_day(now)
    }
  end

  # Mean time from a worker claiming a task to its result coming back, over the
  # most recent completions.
  def average_processing_seconds(now)
    durations = Task.where(status: "completed", completed_at: (now - 24.hours)..).where.not(claimed_at: nil)
                    .order(completed_at: :desc).limit(DURATION_SAMPLE_LIMIT).pluck(:claimed_at, :completed_at)
                    .map { |claimed_at, completed_at| completed_at - claimed_at }.select(&:positive?)
    durations.empty? ? nil : (durations.sum / durations.size).round
  end

  # Oldest first, one entry per UTC day, zero-filled.
  def completed_per_day(now)
    first_day = (now - (DAYS_SHOWN - 1).days).utc.to_date
    counts_by_day = Task.where(status: "completed", completed_at: first_day.beginning_of_day..)
                        .group(Arel.sql("DATE(completed_at)")).count.transform_keys { |day| day.to_s }
    (first_day..now.utc.to_date).map { |day| { date: day.to_s, completed: counts_by_day.fetch(day.to_s, 0) } }
  end
end
