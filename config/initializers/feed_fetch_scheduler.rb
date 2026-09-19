# Per-feed hourly RSS fetching (see Feed#fetch_hour) needs *something* to call
# FeedIngestor.run_scheduled every hour. The documented route is a crontab entry
# running `bin/rails bbc:fetch_scheduled`, but relying solely on that would mean
# a feed's schedule silently does nothing wherever cron isn't configured.
#
# So the app also polls from a background thread whenever it boots as an actual
# server process — same pattern as telegram_autopost_scheduler.rb. Running both
# is safe: FeedIngestor.claim_scheduled_fetch claims each feed with a
# conditional UPDATE, so a feed is fetched at most once per hour slot no matter
# how many sweeps race.
#
# Polls more often than hourly so a feed scheduled for 08:00 is picked up
# shortly after the hour turns, rather than waiting on a sweep that happened to
# start at 07:59.
FEED_FETCH_POLL_INTERVAL = 5.minutes

if defined?(Rails::Server) && !Rails.env.test?
  Rails.application.config.after_initialize do
    Thread.new do
      loop do
        begin
          ActiveRecord::Base.connection_pool.with_connection { FeedIngestor.run_scheduled }
        rescue StandardError => e
          Rails.logger.error "FeedFetchScheduler: #{e.class}: #{e.message}"
          Sentry.capture_exception(e)
        end
        sleep FEED_FETCH_POLL_INTERVAL
      end
    end
  end
end
