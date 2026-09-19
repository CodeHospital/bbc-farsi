# Only initializes Sentry when a DSN is configured (see SentryConfig). With no
# DSN, `Sentry.init` is never called, and every Sentry.* call elsewhere in the
# app (there are many — see the CHANGELOG entry "Report every rescued
# exception to Sentry") becomes a documented no-op courtesy of the sentry-ruby
# gem itself, so nothing needs to be conditionally guarded at each call site.
#
# Never initializes in test, even with a real DSN configured in credentials —
# same reasoning as config/environments/test.rb forcing ActionMailer's :test
# delivery method regardless of RESEND_API_KEY, and as the poller schedulers
# (telegram_autopost_scheduler.rb/feed_fetch_scheduler.rb) skipping test.
# Without this, Sentry's background telemetry thread makes real HTTP calls
# that WebMock rightly blocks (`Real HTTP connections are disabled`),
# spamming every test run with errors instead of just not being reachable.
#
# Deferred to `to_prepare`: at the point config/initializers/*.rb files load,
# application constants like SentryConfig aren't autoloadable yet and
# referencing them raises NameError — see config/initializers/action_mailer.rb
# for the same pattern/explanation.
Rails.application.config.to_prepare do
  next if Rails.env.test?
  next unless SentryConfig.enabled?
  next if Sentry.initialized?

  Sentry.init do |config|
    config.dsn = SentryConfig.dsn
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    # Traces/profiles are billed volume in Sentry; keep this low rather than
    # off so a slow request is still occasionally sampled without flooding a
    # free/low-tier quota under normal traffic.
    config.traces_sample_rate = 0.1
    config.environment = Rails.env
  end
end
