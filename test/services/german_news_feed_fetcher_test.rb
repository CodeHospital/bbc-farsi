require "test_helper"

class GermanNewsFeedFetcherTest < ActiveSupport::TestCase
  VALID_RSS = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>tagesschau.de - Alle Meldungen</title>
        <item>
          <title>Bundestag beschliesst neues Gesetz</title>
          <description>Ein Ueberblick ueber die Abstimmung.</description>
          <link>https://www.tagesschau.de/inland/gesetz-100.html</link>
          <pubDate>#{Time.current.rfc822}</pubDate>
        </item>
        <item>
          <title>Podcast: eine Folge zum Ueberspringen</title>
          <description>Ignoriert.</description>
          <link>https://www.tagesschau.de/podcast-100.html</link>
          <pubDate>#{Time.current.rfc822}</pubDate>
        </item>
      </channel>
    </rss>
  XML

  setup do
    @feed    = Feed.new(name: "tagesschau", url: Feed::GERMANNEWS_FEEDS["tagesschau"][:url], category: "top", source: "germannews")
    @fetcher = GermanNewsFeedFetcher.new
  end

  test "allowlist is derived from the shipped catalog, so the two cannot drift" do
    catalog_hosts = Feed::GERMANNEWS_FEEDS.values.map { |attrs| URI.parse(attrs[:url]).host }.uniq
    assert_equal catalog_hosts.sort, GermanNewsFeedFetcher::ALLOWED_HOSTS.sort
  end

  test "rejects non-https/http schemes" do
    @feed.url = "ftp://www.tagesschau.de/xml/rss2"
    assert_raises(ArgumentError) { @fetcher.fetch(@feed) }
  end

  test "rejects a German host we do not ship a feed for" do
    @feed.url = "https://www.bild.de/rss.xml"
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
    assert_equal "Bundestag beschliesst neues Gesetz", results.first[:title]
  end

  test "every publisher in the catalog is reachable through the allowlist" do
    Feed::GERMANNEWS_FEEDS.each_value do |attrs|
      assert_includes GermanNewsFeedFetcher::ALLOWED_HOSTS, URI.parse(attrs[:url]).host
    end
  end

  test "returns empty array and logs on HTTP error" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    assert_equal [], @fetcher.fetch(@feed)
  end
end
