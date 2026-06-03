ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "webmock/minitest"

# Stub all real HTTP except localhost (Capybara, etc.)
WebMock.disable_net_connect!(allow_localhost: true)

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
  end
end
