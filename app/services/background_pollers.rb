# Lightweight in-process poll loops for the app's periodic work. Each one is
# also available as a cron-able rake task (bin/rails bbc:fetch_scheduled,
# bbc:autopost, bbc:resolve_images), but relying solely on cron would mean the
# work silently stops wherever nobody configured it.
#
# Where they run (see AppRole):
#   - APP_ROLE=all     inside `bin/rails server` (config/initializers/background_pollers.rb)
#   - APP_ROLE=worker  in the dedicated worker service (`bin/rails pollers:run`)
# Never under console/runner/other rake tasks/tests/asset precompile.
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

  # Starts one thread per poller and returns them.
  def start_all = POLLERS.map { |poller| start(poller) }

  def start(poller)
    Thread.new do
      loop do
        begin
          ActiveRecord::Base.connection_pool.with_connection { poller.sweep.call }
        rescue StandardError => e
          Rails.logger.error "#{poller.name}: #{e.class}: #{e.message}"
          Sentry.capture_exception(e)
        end
        sleep poller.interval
      end
    end
  end
end
