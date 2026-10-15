require "test_helper"

class SentryConfigTest < ActiveSupport::TestCase
  test "reads the DSN from Rails credentials" do
    stub_credentials(sentry_dsn: "https://cred@example.ingest.sentry.io/2")

    assert_equal "https://cred@example.ingest.sentry.io/2", SentryConfig.dsn
    assert SentryConfig.enabled?
  end

  test "ignores ENV" do
    ENV["SENTRY_DSN"] = "https://env@example.ingest.sentry.io/1"
    stub_credentials(sentry_dsn: nil)

    assert_nil SentryConfig.dsn
  ensure
    ENV.delete("SENTRY_DSN")
  end

  test "enabled? is false with no DSN configured" do
    stub_credentials(sentry_dsn: "")

    assert_not SentryConfig.enabled?
  end
end
