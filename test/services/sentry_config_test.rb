require "test_helper"

class SentryConfigTest < ActiveSupport::TestCase
  teardown { ENV.delete("SENTRY_DSN") }

  test "prefers Rails credentials over ENV" do
    ENV["SENTRY_DSN"] = "https://env@example.ingest.sentry.io/1"
    Rails.application.credentials.stub(:dig, ->(key) { "https://cred@example.ingest.sentry.io/2" if key == :sentry_dsn }) do
      assert_equal "https://cred@example.ingest.sentry.io/2", SentryConfig.dsn
    end
  end

  test "falls back to ENV when the credential is blank" do
    ENV["SENTRY_DSN"] = "https://env@example.ingest.sentry.io/1"
    Rails.application.credentials.stub(:dig, nil) do
      assert_equal "https://env@example.ingest.sentry.io/1", SentryConfig.dsn
    end
  end

  test "enabled? is false with no DSN configured anywhere" do
    ENV.delete("SENTRY_DSN")
    Rails.application.credentials.stub(:dig, nil) do
      assert_not SentryConfig.enabled?
    end
  end

  test "enabled? is true once a DSN is present" do
    ENV["SENTRY_DSN"] = "https://env@example.ingest.sentry.io/1"
    Rails.application.credentials.stub(:dig, nil) do
      assert SentryConfig.enabled?
    end
  end
end
