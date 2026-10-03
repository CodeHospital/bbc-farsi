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

  test "seed_heise_feeds! creates the heise catalog idempotently" do
    Feed.seed_heise_feeds!
    count_after_first = Feed.count
    Feed.seed_heise_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal Feed::HEISE_FEEDS.size, count_after_first
    assert_equal [ "heise" ], Feed.pluck(:source).uniq
  end

  test "seed_germannews_feeds! creates the German News catalog idempotently" do
    Feed.seed_germannews_feeds!
    count_after_first = Feed.count
    Feed.seed_germannews_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal Feed::GERMANNEWS_FEEDS.size, count_after_first
    assert_equal [ "germannews" ], Feed.pluck(:source).uniq
  end

  test "seeding every catalog keeps the sources distinct" do
    Feed.seed_bbc_feeds!
    Feed.seed_nyt_feeds!
    Feed.seed_adhocnews_feeds!
    Feed.seed_heise_feeds!
    Feed.seed_germannews_feeds!
    Feed.seed_australianews_feeds!
    Feed.seed_israelnews_feeds!
    catalogs = {
      "bbc" => Feed::BBC_FEEDS, "nyt" => Feed::NYT_FEEDS, "adhocnews" => Feed::ADHOCNEWS_FEEDS,
      "heise" => Feed::HEISE_FEEDS, "germannews" => Feed::GERMANNEWS_FEEDS,
      "australianews" => Feed::AUSTRALIANEWS_FEEDS, "israelnews" => Feed::ISRAELNEWS_FEEDS
    }
    assert_equal catalogs.values.sum(&:size), Feed.count
    catalogs.each { |source, catalog| assert_equal catalog.size, Feed.where(source:).count }
  end

  test "every heise feed url is unique and points at an allowed host" do
    urls = Feed::HEISE_FEEDS.values.map { |attrs| attrs[:url] }
    assert_equal urls.uniq.size, urls.size, "duplicate URLs in HEISE_FEEDS would silently no-op in seed_feeds!"

    urls.each do |url|
      host = URI.parse(url).host
      assert_includes %w[www.heise.de www.telepolis.de], host, "#{url} is not on an allowed heise host"
    end
  end

  test "every German News feed url is unique and carries publisher metadata" do
    urls = Feed::GERMANNEWS_FEEDS.values.map { |attrs| attrs[:url] }
    assert_equal urls.uniq.size, urls.size, "duplicate URLs in GERMANNEWS_FEEDS would silently no-op in seed_feeds!"

    Feed::GERMANNEWS_FEEDS.each do |name, attrs|
      publisher = Feed::GERMANNEWS_PUBLISHERS[attrs[:url]]
      assert_equal attrs[:publisher] || name, publisher[:name]
      assert_equal URI.parse(attrs[:site]).host.delete_prefix("www."), publisher[:domain]
      assert publisher[:url].start_with?("https://"), "#{name} publisher url must be absolute"
    end
  end

  test "a public broadcaster with several sections attributes them all to itself" do
    Feed.seed_germannews_feeds!
    inland = Feed.find_by(url: Feed::GERMANNEWS_FEEDS["tagesschau – Inland"][:url])
    ausland = Feed.find_by(url: Feed::GERMANNEWS_FEEDS["tagesschau – Ausland"][:url])

    assert_equal "tagesschau", inland.publisher_info[:name]
    assert_equal "tagesschau", ausland.publisher_info[:name]
    assert_equal inland.publisher_info, ausland.publisher_info
  end

  test "seed_australianews_feeds! creates the Australian News catalog idempotently" do
    Feed.seed_australianews_feeds!
    count_after_first = Feed.count
    Feed.seed_australianews_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal Feed::AUSTRALIANEWS_FEEDS.size, count_after_first
    assert_equal [ "australianews" ], Feed.pluck(:source).uniq
  end

  test "every Australian News feed url is unique and points at an allowed host" do
    urls = Feed::AUSTRALIANEWS_FEEDS.values.map { |attrs| attrs[:url] }
    assert_equal urls.uniq.size, urls.size, "duplicate URLs in AUSTRALIANEWS_FEEDS would silently no-op in seed_feeds!"

    Feed::AUSTRALIANEWS_FEEDS.each do |name, attrs|
      publisher = Feed::AUSTRALIANEWS_PUBLISHERS[attrs[:url]]
      assert_equal name, publisher[:name]
      assert publisher[:url].start_with?("https://"), "#{name} publisher url must be absolute"
    end
  end

  test "seed_israelnews_feeds! creates the Israel News catalog idempotently" do
    Feed.seed_israelnews_feeds!
    count_after_first = Feed.count
    Feed.seed_israelnews_feeds!
    assert_equal count_after_first, Feed.count, "seed is not idempotent"
    assert_equal Feed::ISRAELNEWS_FEEDS.size, count_after_first
    assert_equal [ "israelnews" ], Feed.pluck(:source).uniq
  end

  test "every Israel News feed url is unique and carries publisher metadata" do
    urls = Feed::ISRAELNEWS_FEEDS.values.map { |attrs| attrs[:url] }
    assert_equal urls.uniq.size, urls.size, "duplicate URLs in ISRAELNEWS_FEEDS would silently no-op in seed_feeds!"

    Feed::ISRAELNEWS_FEEDS.each do |name, attrs|
      publisher = Feed::ISRAELNEWS_PUBLISHERS[attrs[:url]]
      assert_equal name, publisher[:name]
    end
  end

  test "publisher_info names the actual publisher for a catalogued German News feed" do
    Feed.seed_germannews_feeds!
    feed = Feed.find_by(url: Feed::GERMANNEWS_FEEDS["ZEIT ONLINE"][:url])

    assert_equal({ name: "ZEIT ONLINE", domain: "zeit.de", url: "https://www.zeit.de" }, feed.publisher_info)
  end

  test "publisher_info falls back to the feed host for an admin-added German News feed" do
    feed = build_feed(source: "germannews", name: "Neues Blatt", url: "https://www.beispiel.de/rss.xml")

    assert_equal({ name: "Neues Blatt", domain: "beispiel.de", url: "https://beispiel.de" }, feed.publisher_info)
  end

  test "publisher_info is nil for single-publisher sources so SOURCE_INFO answers instead" do
    assert_nil build_feed(source: "bbc").publisher_info
    assert_nil build_feed(source: "heise", url: "https://www.heise.de/rss/heise-atom.xml").publisher_info
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

  test "autoposts nowhere (disabled) by default" do
    assert_empty Feed.new.autopost_target_channels
    assert_equal "Disabled", Feed.new.autopost_channel_label
  end

  test "assigning an autopost channel id that doesn't reference a real channel raises" do
    assert_raises(ActiveRecord::RecordNotFound) { build_feed(autopost_target_channel_ids: [ 999_999 ]) }
  end

  test "persists autopost target channels through the join table" do
    channel = create_channel
    feed = create_feed(autopost_target_channel_ids: [ channel.id ])
    assert_equal [ channel ], feed.reload.autopost_target_channels
  end

  test "autopost_channel_label renders the channel name" do
    channel = create_channel(name: "News Channel")
    assert_equal "News Channel", build_feed(autopost_target_channels: [ channel ]).autopost_channel_label
  end

  test "autoposting scope returns only feeds with a channel set" do
    channel = create_channel
    autoposting  = create_feed(url: "https://feeds.bbci.co.uk/news/autoposting.rss", autopost_target_channels: [ channel ])
    not_autoposting = create_feed(url: "https://feeds.bbci.co.uk/news/not-autoposting.rss")
    assert_includes Feed.autoposting, autoposting
    assert_not_includes Feed.autoposting, not_autoposting
  end

  test "autoposts? requires a channel that is both enabled and has its own Autopost toggle on" do
    enabled_and_autopost = create_channel(enabled: true, autopost: true)
    disabled              = create_channel(enabled: false, autopost: true)
    not_autopost          = create_channel(enabled: true, autopost: false)

    assert build_feed(autopost_target_channels: [ enabled_and_autopost ]).autoposts?
    assert_not build_feed(autopost_target_channels: [ disabled ]).autoposts?
    assert_not build_feed(autopost_target_channels: [ not_autopost ]).autoposts?
    assert_not build_feed(autopost_target_channels: []).autoposts?
  end

  test "defaults to bbc source" do
    assert_equal "bbc", Feed.new.source
  end

  test "autopost_channel_label lists every target channel, marking non-Telegram providers" do
    telegram_channel = create_channel(name: "A Telegram")
    bale_channel     = create_channel(name: "B Bale", provider: "bale", channel_id: "@balechannel")
    feed = create_feed(autopost_target_channels: [ telegram_channel, bale_channel ])
    assert_equal "A Telegram, B Bale (Bale)", feed.autopost_channel_label
  end

  test "autoposting scope includes a feed targeting only a non-Telegram channel" do
    bale_channel = create_channel(provider: "bale", channel_id: "@balechannel")
    bale_only    = create_feed(url: "https://feeds.bbci.co.uk/news/bale-only.rss", autopost_target_channels: [ bale_channel ])
    assert_includes Feed.autoposting, bale_only
  end

  test "autopost_channels returns every accepting target across providers, skipping paused ones" do
    telegram_channel = create_channel(name: "A", autopost: true)
    bale_channel     = create_channel(name: "B", provider: "bale", channel_id: "@balechannel", autopost: true)
    custom_channel   = create_channel(name: "C", provider: "custom", custom_provider_name: "Other Messenger",
                                      api_base_url: "https://api.other.example", message_format: "plain",
                                      channel_id: "@other", autopost: true)
    paused_bale      = create_channel(name: "D", provider: "bale", channel_id: "@pausedbale", autopost: false)

    feed = create_feed(autopost_target_channels: [ telegram_channel, bale_channel, custom_channel, paused_bale ])
    assert_equal [ telegram_channel, bale_channel, custom_channel ], feed.autopost_channels
    assert feed.autoposts?

    paused_feed = build_feed(autopost_target_channels: [ paused_bale ])
    assert_empty paused_feed.autopost_channels
    assert_not paused_feed.autoposts?
  end

  test "deleting a feed removes its autopost links but keeps the channels" do
    channel = create_channel
    feed = create_feed(autopost_target_channels: [ channel ])

    assert_difference("FeedAutopostChannel.count", -1) { feed.destroy }
    assert TelegramChannel.exists?(channel.id)
  end
end
