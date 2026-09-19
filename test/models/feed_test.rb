require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "valid with all required attributes" do
    assert build_feed.valid?
  end

  test "invalid without name" do
    assert_not build_feed(name: nil).valid?
  end

  test "invalid without url" do
    assert_not build_feed(url: nil).valid?
  end

  test "invalid without category" do
    assert_not build_feed(category: nil).valid?
  end

  test "url must be unique" do
    fixed_url = "https://feeds.bbci.co.uk/news/fixed-url.rss"
    create_feed(url: fixed_url)
    duplicate = build_feed(url: fixed_url)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:url], "has already been taken"
  end

  test "enabled scope returns only enabled feeds" do
    enabled  = create_feed(url: "https://feeds.bbci.co.uk/news/a.rss", enabled: true)
    disabled = create_feed(url: "https://feeds.bbci.co.uk/news/b.rss", enabled: false)
    assert_includes Feed.enabled, enabled
    assert_not_includes Feed.enabled, disabled
  end

  test "seed_bbc_feeds! creates the BBC catalog idempotently" do
    Feed.seed_bbc_feeds!
    count_after_first = Feed.count
    Feed.seed_bbc_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal Feed::BBC_FEEDS.size, count_after_first
    assert_equal [ "bbc" ], Feed.pluck(:source).uniq
  end

  test "seed_nyt_feeds! creates the NYT catalog idempotently" do
    Feed.seed_nyt_feeds!
    count_after_first = Feed.count
    Feed.seed_nyt_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal Feed::NYT_FEEDS.size, count_after_first
    assert_equal [ "nyt" ], Feed.pluck(:source).uniq
  end

  test "seed_adhocnews_feeds! creates the Ad Hoc News catalog idempotently" do
    Feed.seed_adhocnews_feeds!
    count_after_first = Feed.count
    Feed.seed_adhocnews_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal Feed::ADHOCNEWS_FEEDS.size, count_after_first
    assert_equal [ "adhocnews" ], Feed.pluck(:source).uniq
  end

  test "seeding BBC, NYT, and Ad Hoc News feeds keeps them distinct" do
    Feed.seed_bbc_feeds!
    Feed.seed_nyt_feeds!
    Feed.seed_adhocnews_feeds!
    assert_equal Feed::BBC_FEEDS.size + Feed::NYT_FEEDS.size + Feed::ADHOCNEWS_FEEDS.size, Feed.count
    assert_equal Feed::BBC_FEEDS.size, Feed.where(source: "bbc").count
    assert_equal Feed::NYT_FEEDS.size, Feed.where(source: "nyt").count
    assert_equal Feed::ADHOCNEWS_FEEDS.size, Feed.where(source: "adhocnews").count
  end

  test "every NYT feed url is unique and points at an allowed host" do
    urls = Feed::NYT_FEEDS.values.map { |attrs| attrs[:url] }
    assert_equal urls.uniq.size, urls.size, "duplicate URLs in NYT_FEEDS would silently no-op in seed_feeds!"

    urls.each do |url|
      host = URI.parse(url).host
      assert_includes %w[rss.nytimes.com www.nytimes.com], host, "#{url} is not on an allowed NYT host"
    end
  end

  test "every Ad Hoc News feed url is unique and points at an allowed host" do
    urls = Feed::ADHOCNEWS_FEEDS.values.map { |attrs| attrs[:url] }
    assert_equal urls.uniq.size, urls.size, "duplicate URLs in ADHOCNEWS_FEEDS would silently no-op in seed_feeds!"

    urls.each do |url|
      host = URI.parse(url).host
      assert_includes %w[www.ad-hoc-news.de], host, "#{url} is not on an allowed Ad Hoc News host"
    end
  end

  test "invalid with an unknown source" do
    assert_not build_feed(source: "cnn").valid?
  end

  test "fetch_hour is nil (unscheduled) by default" do
    assert_nil Feed.new.fetch_hour
    assert_equal "Disabled", Feed.new.fetch_schedule_label
  end

  test "fetch_hour accepts every hour of the day" do
    Feed::FETCH_HOURS.each { |hour| assert build_feed(fetch_hour: hour).valid?, "hour #{hour} should be valid" }
    assert_equal 24, Feed::FETCH_HOURS.size
  end

  test "invalid with an out-of-range fetch_hour" do
    assert_not build_feed(fetch_hour: 24).valid?
    assert_not build_feed(fetch_hour: -1).valid?
  end

  test "fetch_schedule_label renders a zero-padded hour" do
    assert_equal "08:00", build_feed(fetch_hour: 8).fetch_schedule_label
    assert_equal "23:00", build_feed(fetch_hour: 23).fetch_schedule_label
  end

  test "scheduled scope returns only feeds with an hour set" do
    scheduled   = create_feed(url: "https://feeds.bbci.co.uk/news/sched.rss", fetch_hour: 8)
    unscheduled = create_feed(url: "https://feeds.bbci.co.uk/news/unsched.rss", fetch_hour: nil)
    assert_includes Feed.scheduled, scheduled
    assert_not_includes Feed.scheduled, unscheduled
  end

  test "defaults to bbc source" do
    assert_equal "bbc", Feed.new.source
  end
end
