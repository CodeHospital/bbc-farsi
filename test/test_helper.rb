ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "webmock/minitest"

# Stub all real HTTP except localhost (Capybara, etc.)
WebMock.disable_net_connect!(allow_localhost: true)

# Never read the real llmarkt credentials/ENV in tests. With them set, every
# Task created in the suite would fire its after_create_commit auto-submit at the
# live grid. Default llmarkt OFF here; tests that exercise it opt in explicitly
# via `stub_llmarkt_config` (see ActiveSupport::TestCase below).
%i[api_url api_key app_base_url].each do |llmarkt_config_method|
  Llmarkt.define_singleton_method(llmarkt_config_method) { nil }
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    # ── Fixture helpers ──────────────────────────────────────────────────────

    def build_feed(attrs = {})
      # unique URL per call so tests that create multiple feeds don't collide
      Feed.new({ name: "Technology", url: "https://feeds.bbci.co.uk/news/test-#{SecureRandom.hex(6)}.rss", category: "technology" }.merge(attrs))
    end

    def create_feed(attrs = {})
      build_feed(attrs).tap(&:save!)
    end

    def create_article(feed: nil, attrs: {})
      feed ||= create_feed
      Article.create!({
        feed:,
        title:       "Test article title",
        url:         "https://www.bbc.co.uk/news/test-#{SecureRandom.hex(4)}",
        description: "A short test description.",
        status:      "pending"
      }.merge(attrs))
    end

    def create_rewrite(article: nil, attrs: {})
      article ||= create_article
      Rewrite.create!({ article:, llm_model: "qwen3:14b", status: "completed", content: "Rewritten text." }.merge(attrs))
    end

    def create_translation(rewrite: nil, attrs: {})
      rewrite ||= create_rewrite
      Translation.create!({
        rewrite:,
        article:         rewrite.article,
        llm_model:       "aya-expanse:32b",
        prompt_name:     "prompt",
        translated_title: "عنوان",
        translated_body:  "متن ترجمه شده",
        status:          "completed"
      }.merge(attrs))
    end

    def create_channel(attrs = {})
      TelegramChannel.create!({ name: "Test Channel", token: "123:abc", channel_id: "@testchannel" }.merge(attrs))
    end

    ADMIN_CREDENTIALS = ActionController::HttpAuthentication::Basic.encode_credentials("testadmin", "testpass")

    # ── llmarkt test helpers ──────────────────────────────────────────────────
    # Override Llmarkt's config deterministically so tests never depend on (or
    # reach) the real grid configured in Rails credentials / ENV. Tests still
    # stub LlmarktClient or WebMock for the actual HTTP.

    LLMARKT_TEST_CONFIG = {
      api_url:      "https://llmarkt.test/api/v1",
      api_key:      "test-key",
      app_base_url: "https://app.test"
    }.freeze

    def stub_llmarkt_config(**overrides)
      @llmarkt_config_originals ||= {}
      LLMARKT_TEST_CONFIG.merge(overrides).each do |name, value|
        @llmarkt_config_originals[name] ||= Llmarkt.method(name)
        Llmarkt.define_singleton_method(name) { value }
      end
    end

    def restore_llmarkt_config
      @llmarkt_config_originals&.each { |name, meth| Llmarkt.define_singleton_method(name, meth) }
      @llmarkt_config_originals = nil
    end

    # Run a block with llmarkt forced off (e.g. to create a task without firing
    # the after_create_commit auto-submit), then restore the previous behaviour.
    def with_llmarkt_disabled
      original = Llmarkt.method(:enabled?)
      Llmarkt.define_singleton_method(:enabled?) { false }
      yield
    ensure
      Llmarkt.define_singleton_method(:enabled?, original)
    end
  end
end
