# Delivering a queued Telegram post (see Publisher/Autoposter) needs
# *something* to periodically call Autoposter.run_all. The app has no in-app
# job queue — LLM work stays on the external Ollama worker, driven by cron
# hitting `bin/rails bbc:autopost` (see lib/tasks/bbc.rake) — but relying
# solely on that external cron would mean Telegram posting silently stops
# the moment nobody's configured it, which defeats the whole point of pacing
# posts out over time instead of firing them instantly.
#
# So the app also runs its own lightweight poll loop in a background thread
# whenever it boots as an actual server process. It's harmless to run
# alongside an external `bbc:autopost` cron too — `Publisher.deliver_pending!`
# claims a post with a conditional UPDATE before sending, so two concurrent
# sweeps (this thread + cron, or multiple Puma workers) can't double-send.
#
# Only starts under `bin/rails server` (`Rails::Server` is defined there) —
# never under console/runner/rake tasks/tests/asset precompile, so a one-off
# `bin/rails runner` script or the test suite never spawns a stray thread.
TELEGRAM_AUTOPOST_POLL_INTERVAL = 1.minute

if defined?(Rails::Server) && !Rails.env.test?
  Rails.application.config.after_initialize do
    Thread.new do
      loop do
        begin
          ActiveRecord::Base.connection_pool.with_connection { Autoposter.run_all }
        rescue StandardError => e
          Rails.logger.error "TelegramAutopostScheduler: #{e.class}: #{e.message}"
          Sentry.capture_exception(e)
        end
        sleep TELEGRAM_AUTOPOST_POLL_INTERVAL
      end
    end
  end
end
