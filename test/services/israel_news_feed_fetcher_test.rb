require "test_helper"

class IsraelNewsFeedFetcherTest < ActiveSupport::TestCase
  VALID_RSS = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Haaretz</title>
        <item>
          <title>Government announces new policy</title>
          <description>An overview of the announcement.</description>
          <link>https://www.haaretz.com/israel-news/2026-09-20/policy-announcement</link>
          <pubDate>#{Time.current.rfc822}</pubDate>
        </item>
        <item>
          <title>Podcast: an episode to skip</title>
          <description>Ignored.</description>
          <link>https://www.haaretz.com/podcast/12345</link>
          <pubDate>#{Time.current.rfc822}</pubDate>
        </item>
      </channel>
    </rss>
  XML

  setup do
    @feed    = Feed.new(name: "Haaretz", url: Feed::ISRAELNEWS_FEEDS["Haaretz"][:url], category: "top", source: "israelnews")
    @fetcher = IsraelNewsFeedFetcher.new
  end

  test "allowlist is derived from the shipped catalog, so the two cannot drift" do
    catalog_hosts = Feed::ISRAELNEWS_FEEDS.values.map { |attrs| URI.parse(attrs[:url]).host }.uniq
    assert_equal catalog_hosts.sort, IsraelNewsFeedFetcher::ALLOWED_HOSTS.sort
  end

  test "rejects non-https/http schemes" do
    @feed.url = "ftp://www.haaretz.com/srv/haaretz-latest-headlines"
    assert_raises(ArgumentError) { @fetcher.fetch(@feed) }
  end

  test "rejects an Israeli host we do not ship a feed for" do
    @feed.url = "https://www.timesofisrael.com/rss.xml"
    assert_raises(ArgumentError) { @fetcher.fetch(@feed) }
  end

  test "rejects internal IP addresses dressed as valid hosts (not in allowlist)" do
    @feed.url = "http://192.168.1.1/rss.xml"
    assert_raises(ArgumentError) { @fetcher.fetch(@feed) }
  end

  test "fetches and parses entries from an allowed host" do
    stub_request(:get, @feed.url).to_return(body: VALID_RSS, headers: { "Content-Type" => "application/rss+xml" })

    results = @fetcher.fetch(@feed)
    assert_equal 1, results.size, "should filter out the ignored 'Podcast:' entry"
    assert_equal "Government announces new policy", results.first[:title]
  end

  test "every publisher in the catalog is reachable through the allowlist" do
    Feed::ISRAELNEWS_FEEDS.each_value do |attrs|
      assert_includes IsraelNewsFeedFetcher::ALLOWED_HOSTS, URI.parse(attrs[:url]).host
    end
  end

  test "returns empty array and logs on HTTP error" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    assert_equal [], @fetcher.fetch(@feed)
  end
end
