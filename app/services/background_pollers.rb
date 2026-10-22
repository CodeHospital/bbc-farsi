# Lightweight in-process poll loops for the app's periodic work. Each one is
# also available as a cron-able rake task (bin/rails bbc:fetch_scheduled,
# bbc:autopost, bbc:resolve_images), but relying solely on cron would mean the
# work silently stops wherever nobody configured it.
#
# Where they run (see AppRole):
#   - inside `bin/rails server` for APP_ROLE=all and APP_ROLE=worker (the worker
#     service, which also serves their status page — WorkerStatusController)
#   - or headless via `bin/rails pollers:run`
# Never under console/runner/other rake tasks/tests/asset precompile.
#
# Each sweep records a heartbeat (last run, duration, error) in Rails.cache —
# Solid Cache in production, so it is shared across containers and survives
# restarts without a table of its own.
#
# Running several copies (cron + poller, several Puma workers, several
# containers) is safe: each sweep claims its rows with a conditional UPDATE
# before doing anything — FeedIngestor.claim_scheduled_fetch,
# Publisher.deliver_pending!, ArticleImageResolver.
module BackgroundPollers
  module_function

  Poller = Data.define(:name, :interval, :sweep)

  POLLERS = [
    # Per-feed hourly RSS fetching (Feed#fetch_hour). Polls more often than
    # hourly so a feed scheduled for 08:00 is picked up shortly after the hour
    # turns rather than waiting on a sweep that happened to start at 07:59.
    Poller.new(name: "FeedFetchScheduler", interval: 5.minutes, sweep: -> { FeedIngestor.run_scheduled }),

    # Delivers queued Telegram posts, paced out over time (Publisher/Autoposter).
    Poller.new(name: "TelegramAutopostScheduler", interval: 1.minute, sweep: -> { Autoposter.run_all }),

    # Resolves articles' lead images in the background, never in a visitor's
    # request (ArticleImageResolver).
    Poller.new(name: "ArticleImageScheduler", interval: 2.minutes, sweep: -> { ArticleImageResolver.resolve_pending })
  ].freeze

  # A poller counts as stalled once it has missed this many intervals.
  STALLED_AFTER_INTERVALS = 3

  HEARTBEAT_EXPIRY = 7.days

  # Starts one thread per poller and returns them.
  def start_all
    Rails.cache.write(process_cache_key, { hostname: Socket.gethostname, role: AppRole.current, started_at: Time.current },
                      expires_in: HEARTBEAT_EXPIRY)
    POLLERS.map { |poller| start(poller) }
  end

  def start(poller)
    Thread.new do
      loop do
        run_once(poller)
        sleep poller.interval
      end
    end
  end

  def run_once(poller)
    started_at = Time.current
    sweep_error = nil
    begin
      ActiveRecord::Base.connection_pool.with_connection { poller.sweep.call }
    rescue StandardError => e
      sweep_error = e
      Rails.logger.error "#{poller.name}: #{e.class}: #{e.message}"
      Sentry.capture_exception(e)
    end
    record_heartbeat(poller, started_at:, sweep_error:)
  end

  def record_heartbeat(poller, started_at:, sweep_error:)
    previous_heartbeat = heartbeat(poller) || {}
    Rails.cache.write(heartbeat_cache_key(poller), {
      last_run_at:      started_at,
      duration_seconds: (Time.current - started_at).round(2),
      hostname:         Socket.gethostname,
      run_count:        previous_heartbeat.fetch(:run_count, 0) + 1,
      error_count:      previous_heartbeat.fetch(:error_count, 0) + (sweep_error ? 1 : 0),
      last_error:       (sweep_error && "#{sweep_error.class}: #{sweep_error.message}"),
      last_error_at:    (sweep_error ? started_at : previous_heartbeat[:last_error_at])
    }, expires_in: HEARTBEAT_EXPIRY)
  rescue StandardError => e
    Rails.logger.error "BackgroundPollers: could not record heartbeat for #{poller.name}: #{e.class}: #{e.message}"
  end

  # Last recorded run of a poller (any container), or nil if never seen.
  def heartbeat(poller) = Rails.cache.read(heartbeat_cache_key(poller))

  # The process that last started the pollers (hostname, role, started_at).
  def process_info = Rails.cache.read(process_cache_key)

  # :ok, :failing (last sweep raised), :stalled (missed several intervals)
  # or :never_run.
  def health(poller, now: Time.current)
    last_heartbeat = heartbeat(poller)
    return :never_run if last_heartbeat.nil?
    return :stalled if last_heartbeat[:last_run_at] < now - (poller.interval * STALLED_AFTER_INTERVALS)

    last_heartbeat[:last_error] ? :failing : :ok
  end

  def heartbeat_cache_key(poller) = "background_pollers/heartbeat/#{poller.name}"
  def process_cache_key = "background_pollers/process"
end
