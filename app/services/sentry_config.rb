# Configuration for error tracking (Sentry).
#
# Credentials are read from Rails credentials first, then ENV as a fallback:
#   credentials.sentry_dsn / ENV["SENTRY_DSN"]
#
# Same pattern as MailerConfig/Llmarkt: no DSN configured means Sentry stays
# fully inert (config/initializers/sentry.rb never calls Sentry.init), so
# every Sentry.capture_exception call throughout the app is a safe no-op
# until a real DSN is set.
module SentryConfig
  module_function

  def dsn
    Rails.application.credentials.dig(:sentry_dsn) || ENV["SENTRY_DSN"]
  end

  def enabled?
    dsn.present?
  end
end
