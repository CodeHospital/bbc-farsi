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

  test "routes NYT feeds to NytFeedFetcher and BBC feeds to BbcFeedFetcher" do
    nyt_feed = create_feed(source: "nyt", url: "https://rss.nytimes.com/services/xml/rss/nyt/test-#{SecureRandom.hex(6)}.xml")

    bbc_fake = Object.new
    bbc_fake.define_singleton_method(:fetch) { |_feed| [] }
    nyt_fake = Object.new
    seen_feed_ids = []
    nyt_fake.define_singleton_method(:fetch) { |feed| seen_feed_ids << feed.id; [] }

    BbcFeedFetcher.stub(:new, bbc_fake) do
      NytFeedFetcher.stub(:new, nyt_fake) { FeedIngestor.run }
    end

    assert_equal [ nyt_feed.id ], seen_feed_ids
  end

  test "routes Ad Hoc News feeds to AdhocnewsFeedFetcher" do
    adhocnews_feed = create_feed(source: "adhocnews", url: "https://www.ad-hoc-news.de/rss/test-#{SecureRandom.hex(6)}.xml")

    bbc_fake = Object.new
    bbc_fake.define_singleton_method(:fetch) { |_feed| [] }
    adhocnews_fake = Object.new
    seen_feed_ids = []
    adhocnews_fake.define_singleton_method(:fetch) { |feed| seen_feed_ids << feed.id; [] }

    BbcFeedFetcher.stub(:new, bbc_fake) do
      AdhocnewsFeedFetcher.stub(:new, adhocnews_fake) { FeedIngestor.run }
    end

    assert_equal [ adhocnews_feed.id ], seen_feed_ids
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

  test "run_one creates a new article, enqueues a task, and reports ignored entries" do
    report = {
      entries: [ { title: "Story A", url: "https://bbc.co.uk/news/a", description: "d", published_at: Time.current, status: "pending" } ],
      ignored: [ { title: "Watch: clip", url: "https://bbc.co.uk/news/watch-1", reason: "title starts with ignored prefix \"Watch:\"" } ],
      error: nil
    }

    result = nil
    stub_fetcher_report(returns: report) do
      assert_difference([ "Article.count", "Task.count" ], 1) { result = FeedIngestor.run_one(@feed) }
    end

    assert_equal 1, result[:new_count]
    assert_equal 0, result[:updated_count]
    assert_equal 1, result[:skipped].size
    assert_match(/Watch:/, result[:skipped].first[:reason])
  end

  test "run_one updates an existing article whose content changed" do
    existing = create_article(feed: @feed, attrs: { title: "Old title", description: "old desc" })
    report = {
      entries: [ { title: "New title", url: existing.url, description: "old desc", published_at: existing.published_at, status: "pending" } ],
      ignored: [],
      error: nil
    }

    result = nil
    stub_fetcher_report(returns: report) do
      assert_no_difference("Article.count") { result = FeedIngestor.run_one(@feed) }
    end

    assert_equal 0, result[:new_count]
    assert_equal 1, result[:updated_count]
    assert_equal "New title", existing.reload.title
  end

  test "run_one skips an existing article with no changes and explains why" do
    existing = create_article(feed: @feed, attrs: { title: "Same title", description: "same desc" })
    report = {
      entries: [ { title: "Same title", url: existing.url, description: "same desc", published_at: existing.published_at, status: "pending" } ],
      ignored: [],
      error: nil
    }

    result = nil
    stub_fetcher_report(returns: report) do
      assert_no_difference("Article.count") { result = FeedIngestor.run_one(@feed) }
    end

    assert_equal 0, result[:new_count]
    assert_equal 0, result[:updated_count]
    assert_equal 1, result[:skipped].size
    assert_equal "already up to date", result[:skipped].first[:reason]
  end

  test "run_one surfaces a fetch error without touching articles" do
    report = { entries: [], ignored: [], error: "timeout" }

    result = nil
    stub_fetcher_report(returns: report) do
      assert_no_difference("Article.count") { result = FeedIngestor.run_one(@feed) }
    end

    assert_equal "timeout", result[:error]
    assert_equal 0, result[:new_count]
    assert_equal 0, result[:updated_count]
    assert_equal [], result[:skipped]
  end

  test "run_scheduled fetches only feeds scheduled for the current hour" do
    @feed.update!(fetch_hour: 8)
    other_hour  = create_feed(url: "https://feeds.bbci.co.uk/news/nine.rss", fetch_hour: 9)
    unscheduled = create_feed(url: "https://feeds.bbci.co.uk/news/none.rss", fetch_hour: nil)

    result = nil
    fetched_ids = record_fetched_feed_ids { result = FeedIngestor.run_scheduled(at_hour(8)) }

    assert_equal [ @feed.id ], fetched_ids
    assert_not_includes fetched_ids, other_hour.id
    assert_not_includes fetched_ids, unscheduled.id
    assert_equal 1, result[:feed_count]
  end

  test "run_scheduled skips a scheduled feed that is disabled" do
    @feed.update!(fetch_hour: 8, enabled: false)

    result = nil
    fetched_ids = record_fetched_feed_ids { result = FeedIngestor.run_scheduled(at_hour(8)) }

    assert_empty fetched_ids
    assert_equal 0, result[:feed_count]
  end

  test "run_scheduled ingests articles and enqueues rewrite tasks like a manual fetch" do
    @feed.update!(fetch_hour: 8)
    new_articles = [
      { title: "Story A", url: "https://bbc.co.uk/news/a", description: "d", published_at: Time.current, status: "pending" }
    ]

    result = nil
    stub_fetcher(returns: new_articles) do
      assert_difference([ "Article.count", "Task.count" ], 1) do
        result = FeedIngestor.run_scheduled(at_hour(8))
      end
    end

    assert_equal 1, result[:new_count]
    assert_equal 1, result[:feed_count]
  end

  test "run_scheduled fetches a feed at most once per hour slot" do
    @feed.update!(fetch_hour: 8)

    first_sweep  = record_fetched_feed_ids { FeedIngestor.run_scheduled(at_hour(8, minute: 0)) }
    second_sweep = record_fetched_feed_ids { FeedIngestor.run_scheduled(at_hour(8, minute: 30)) }

    assert_equal [ @feed.id ], first_sweep
    assert_empty second_sweep, "a second sweep in the same hour should not re-fetch the feed"
  end

  test "run_scheduled fetches again once the hour slot turns over" do
    @feed.update!(fetch_hour: 8)
    record_fetched_feed_ids { FeedIngestor.run_scheduled(at_hour(8)) }

    @feed.update!(fetch_hour: 9)
    next_hour_sweep = record_fetched_feed_ids { FeedIngestor.run_scheduled(at_hour(9)) }

    assert_equal [ @feed.id ], next_hour_sweep
  end

  test "run_scheduled records when a feed was last auto-fetched" do
    @feed.update!(fetch_hour: 8)
    assert_nil @feed.last_scheduled_fetch_at

    record_fetched_feed_ids { FeedIngestor.run_scheduled(at_hour(8)) }

    assert_not_nil @feed.reload.last_scheduled_fetch_at
  end

  private

  # A local Time in the given hour — run_scheduled compares against the
  # server's local clock (Time.now), not Time.zone.
  def at_hour(hour, minute: 0)
    Time.new(2026, 9, 19, hour, minute, 0)
  end

  # Runs the block with every fetcher stubbed out, returning the ids of the
  # feeds that actually got fetched.
  def record_fetched_feed_ids(&block)
    fetched_ids = []
    fake = Object.new
    fake.define_singleton_method(:fetch) { |feed| fetched_ids << feed.id; [] }
    BbcFeedFetcher.stub(:new, fake, &block)
    fetched_ids
  end

  def stub_fetcher(returns:, &block)
    fake = Object.new
    fake.define_singleton_method(:fetch) { |_feed| returns }
    BbcFeedFetcher.stub(:new, fake, &block)
  end

  def stub_fetcher_report(returns:, &block)
    fake = Object.new
    fake.define_singleton_method(:fetch_with_report) { |_feed| returns }
    BbcFeedFetcher.stub(:new, fake, &block)
  end
end
