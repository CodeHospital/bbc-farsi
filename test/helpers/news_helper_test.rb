require "test_helper"

class NewsHelperTest < ActionView::TestCase
  include NewsHelper

  # ── publisher attribution ───────────────────────────────────────────────────

  test "a single-publisher source is identified by SOURCE_INFO" do
    feed = Feed.new(name: "Top News", url: "https://feeds.bbci.co.uk/news/rss.xml", category: "top", source: "bbc")

    assert_equal "BBC News", source_name(feed)
    assert_equal "bbc.com", source_domain(feed)
    assert_equal "https://www.bbc.com/news", source_url(feed)
  end

  test "heise is identified by SOURCE_INFO even for its Telepolis feed" do
    feed = Feed.new(name: "Telepolis", url: "https://www.telepolis.de/feed.xml", category: "politics", source: "heise")

    assert_equal "heise online", source_name(feed)
    assert_equal "heise.de", source_domain(feed)
  end

  test "each German News feed is attributed to its own publisher, not to the source" do
    zeit = Feed.new(name: "ZEIT ONLINE", url: Feed::GERMANNEWS_FEEDS["ZEIT ONLINE"][:url], category: "top", source: "germannews")
    taz  = Feed.new(name: "taz", url: Feed::GERMANNEWS_FEEDS["taz"][:url], category: "top", source: "germannews")

    assert_equal "ZEIT ONLINE", source_name(zeit)
    assert_equal "zeit.de", source_domain(zeit), "must use the article host, not the newsfeed.zeit.de feed host"
    assert_equal "https://www.zeit.de", source_url(zeit)

    assert_equal "taz", source_name(taz)
    assert_equal "taz.de", source_domain(taz)
  end

  test "an unknown source still renders without blowing up" do
    feed = Feed.new(name: "Whatever", url: "https://example.com/rss.xml", category: "top", source: "unknown")

    assert_equal "unknown", source_name(feed)
    assert_equal "", source_domain(feed)
  end

  # ── categories ──────────────────────────────────────────────────────────────

  test "the local category used by the regional German papers is labelled in both editions" do
    assert_equal "اخبار محلی", NewsHelper::CATEGORY_NAMES_FA["local"]
    assert_equal "Local", NewsHelper::CATEGORY_NAMES_EN["local"]
    assert_not_equal "#dd3333", category_color("local"), "local should have its own accent, not the fallback"
  end

  test "every category shipped in a feed catalog has a Persian label" do
    catalogs = [
      Feed::BBC_FEEDS, Feed::HEISE_FEEDS, Feed::GERMANNEWS_FEEDS,
      Feed::AUSTRALIANEWS_FEEDS, Feed::ISRAELNEWS_FEEDS
    ]
    categories = catalogs.flat_map { |catalog| catalog.values.map { |attrs| attrs[:category] } }.uniq

    missing = categories.reject { |category| NewsHelper::CATEGORY_NAMES_FA.key?(category) }
    assert_equal [ "autos" ], missing, "unlabelled categories beyond the known 'autos' gap: #{missing.inspect}"
  end

  test "each multi-publisher source is attributed to its own catalogued publisher" do
    au = Feed.new(name: "ABC News", url: Feed::AUSTRALIANEWS_FEEDS["ABC News"][:url], category: "top", source: "australianews")
    il = Feed.new(name: "Haaretz", url: Feed::ISRAELNEWS_FEEDS["Haaretz"][:url], category: "top", source: "israelnews")

    assert_equal "ABC News", source_name(au)
    assert_equal "abc.net.au", source_domain(au)

    assert_equal "Haaretz", source_name(il)
    assert_equal "haaretz.com", source_domain(il)
  end
end
