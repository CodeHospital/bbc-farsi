# Configuration for error tracking (Sentry).
#
# Read from Rails credentials (see AppCredentials): sentry_dsn.
#
# Same pattern as MailerConfig/Llmarkt: no DSN configured means Sentry stays
# fully inert (config/initializers/sentry.rb never calls Sentry.init), so
# every Sentry.capture_exception call throughout the app is a safe no-op
# until a real DSN is set.
module SentryConfig
  module_function

  def dsn
    AppCredentials.fetch(:sentry_dsn)
  end

  def enabled?
    dsn.present?
  end
end
