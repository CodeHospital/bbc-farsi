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

  test "seed_bbc_feeds! creates 7 feeds idempotently" do
    Feed.seed_bbc_feeds!
    count_after_first = Feed.count
    Feed.seed_bbc_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal 7, count_after_first
  end
end
