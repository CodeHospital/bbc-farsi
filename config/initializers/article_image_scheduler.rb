# Lead images are resolved in the background (ArticleImageResolver), never in
# a visitor's request. The documented route is a crontab entry running
# `bin/rails bbc:resolve_images`, but relying on that alone would leave new
# articles on their (small) feed thumbnails wherever cron isn't configured.
#
# So the app also polls from a background thread whenever it boots as an
# actual server process — same pattern as feed_fetch_scheduler.rb. Running both
# is safe: ArticleImageResolver claims each article with a conditional UPDATE.
ARTICLE_IMAGE_POLL_INTERVAL = 2.minutes

if defined?(Rails::Server) && !Rails.env.test?
  Rails.application.config.after_initialize do
    Thread.new do
      loop do
        begin
          ActiveRecord::Base.connection_pool.with_connection { ArticleImageResolver.resolve_pending }
        rescue StandardError => e
          Rails.logger.error "ArticleImageScheduler: #{e.class}: #{e.message}"
          Sentry.capture_exception(e)
        end
        sleep ARTICLE_IMAGE_POLL_INTERVAL
      end
    end
  end
end
