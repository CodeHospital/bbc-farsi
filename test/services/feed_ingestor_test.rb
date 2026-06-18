require "test_helper"

class FeedIngestorTest < ActiveSupport::TestCase
  setup do
    @feed   = create_feed(enabled: true)
    @server = OllamaServer.create!(name: "Local", url: "http://localhost:11434",
                                   rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b")
  end

  test "creates articles and a rewrite Task per new article" do
    new_articles = [
      { title: "Story A", url: "https://bbc.co.uk/news/a", description: "d", published_at: Time.current, status: "pending" },
      { title: "Story B", url: "https://bbc.co.uk/news/b", description: "d", published_at: Time.current, status: "pending" }
    ]

    stub_fetcher(returns: new_articles) do
      assert_difference([ "Article.count", "Task.count" ], 2) do
        assert_equal 2, FeedIngestor.run
      end
    end

    assert_equal %w[rewrite rewrite], Task.order(:id).last(2).map(&:kind)
  end

  test "skips already-existing articles and creates no tasks for them" do
    existing = create_article(feed: @feed)
    known    = [ { title: existing.title, url: existing.url, description: "d", published_at: Time.current, status: "pending" } ]

    stub_fetcher(returns: known) do
      assert_no_difference([ "Article.count", "Task.count" ]) do
        assert_equal 0, FeedIngestor.run
      end
    end
  end

  test "skips disabled feeds" do
    @feed.update!(enabled: false)
    fetched = false

    fake = Object.new
    fake.define_singleton_method(:fetch) { |_feed| fetched = true; [] }
    BbcFeedFetcher.stub(:new, fake) { FeedIngestor.run }

    assert_not fetched, "fetcher should not be called for disabled feeds"
  end

  test "still ingests articles when no Ollama server is configured (no task)" do
    OllamaServer.delete_all
    new_articles = [ { title: "Story A", url: "https://bbc.co.uk/news/a", description: "d", published_at: Time.current, status: "pending" } ]

    stub_fetcher(returns: new_articles) do
      assert_difference("Article.count", 1) do
        assert_no_difference("Task.count") { FeedIngestor.run }
      end
    end
  end

  private

  def stub_fetcher(returns:, &block)
    fake = Object.new
    fake.define_singleton_method(:fetch) { |_feed| returns }
    BbcFeedFetcher.stub(:new, fake, &block)
  end
end
