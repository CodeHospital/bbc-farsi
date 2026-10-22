module WorkerStatusHelper
  POLLER_HEALTH_LABELS = { ok: "OK", failing: "Failing", stalled: "Stalled", never_run: "Not running" }.freeze

  def poller_health_badge(health)
    tag.span(POLLER_HEALTH_LABELS.fetch(health), class: "badge health-#{health}")
  end

  def worker_time_ago(time)
    time ? "#{time_ago_in_words(time)} ago" : "never"
  end

  def worker_duration(seconds)
    return "—" if seconds.nil?
    return "#{seconds}s" if seconds < 60

    distance_of_time_in_words(seconds)
  end
end
