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

  test "France 24 is identified by SOURCE_INFO" do
    feed = Feed.new(name: "World", url: "https://www.france24.com/en/rss", category: "world", source: "france24")

    assert_equal "France 24", source_name(feed)
    assert_equal "france24.com", source_domain(feed)
  end

  test "Le Monde and Le Figaro are identified by SOURCE_INFO" do
    monde = Feed.new(name: "Culture", url: "https://www.lemonde.fr/en/culture/rss_full.xml", category: "arts", source: "lemonde")
    figaro = Feed.new(name: "Latest news", url: "https://www.lefigaro.fr/rss/figaro_actualites.xml", category: "top", source: "lefigaro")

    assert_equal "Le Monde", source_name(monde)
    assert_equal "lemonde.fr", source_domain(monde)
    assert_equal "Le Figaro", source_name(figaro)
    assert_equal "lefigaro.fr", source_domain(figaro)
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
      Feed::AUSTRALIANEWS_FEEDS, Feed::ISRAELNEWS_FEEDS, Feed::FRANCE24_FEEDS,
      Feed::LEMONDE_FEEDS, Feed::LEFIGARO_FEEDS
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

  # ── tag page fragment cache key ─────────────────────────────────────────────

  FakeVersioned = Struct.new(:id, :cache_key_with_version)
  FakeStory     = Struct.new(:cache_key_with_version, :article)

  def fake_story(article_id, story_version: "translations/#{article_id}-1", article_version: "articles/#{article_id}-1")
    FakeStory.new(story_version, FakeVersioned.new(article_id, article_version))
  end

  test "the tag list cache key changes when a listed story, its article, its image or the list changes" do
    tag = FakeVersioned.new(7, "tags/7-1")
    stories = [ fake_story(1), fake_story(2) ]
    image_urls = { 1 => "https://img/1.jpg", 2 => nil }
    base_key = news_tag_list_cache_key(tag, stories, image_urls, "fa")

    assert_equal base_key, news_tag_list_cache_key(tag, [ fake_story(1), fake_story(2) ], image_urls.dup, "fa")
    assert_not_equal base_key, news_tag_list_cache_key(tag, stories, image_urls, "en")
    assert_not_equal base_key, news_tag_list_cache_key(tag, [ fake_story(1) ], image_urls, "fa")
    assert_not_equal base_key, news_tag_list_cache_key(tag, [ fake_story(1, story_version: "translations/1-2"), fake_story(2) ], image_urls, "fa")
    assert_not_equal base_key, news_tag_list_cache_key(tag, [ fake_story(1, article_version: "articles/1-2"), fake_story(2) ], image_urls, "fa")
    assert_not_equal base_key, news_tag_list_cache_key(tag, stories, image_urls.merge(2 => "https://img/2.jpg"), "fa")

    # A renamed tag shown under an item busts the list too.
    item_tags = { 1 => [ FakeVersioned.new(9, "tags/9-1") ] }
    renamed_item_tags = { 1 => [ FakeVersioned.new(9, "tags/9-2") ] }
    assert_not_equal news_tag_list_cache_key(tag, stories, image_urls, "fa", item_tags),
                     news_tag_list_cache_key(tag, stories, image_urls, "fa", renamed_item_tags)
  end
end
