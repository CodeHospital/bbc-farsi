require "test_helper"

class NytFeedFetcherTest < ActiveSupport::TestCase
  VALID_RSS = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <item>
        <title>Markets rally on earnings news</title>
        <link>https://www.nytimes.com/2026/07/03/business/markets.html</link>
        <description>A business summary.</description>
        <pubDate>#{Time.current.rfc2822}</pubDate>
      </item>
      <item>
        <title>Watch: something to skip</title>
        <link>https://www.nytimes.com/video/watch-456.html</link>
        <description>Ignored.</description>
        <pubDate>#{Time.current.rfc2822}</pubDate>
      </item>
    </channel></rss>
  XML

  setup do
    @feed    = Feed.new(name: "Business", url: "https://rss.nytimes.com/services/xml/rss/nyt/Business.xml", category: "business", source: "nyt")
    @fetcher = NytFeedFetcher.new
  end

  test "rejects non-https/http schemes" do
    @feed.url = "ftp://rss.nytimes.com/services/xml/rss/nyt/Business.xml"
    assert_raises(ArgumentError) { @fetcher.fetch(@feed) }
  end

  test "rejects URLs with disallowed hostname" do
    @feed.url = "https://evil.example.com/rss.xml"
    assert_raises(ArgumentError) { @fetcher.fetch(@feed) }
  end

  test "rejects internal IP addresses dressed as valid hosts (not in allowlist)" do
    @feed.url = "http://192.168.1.1/rss.xml"
    assert_raises(ArgumentError) { @fetcher.fetch(@feed) }
  end

  test "fetches and parses entries from an allowed host" do
    stub_request(:get, @feed.url).to_return(body: VALID_RSS, headers: { "Content-Type" => "application/rss+xml" })

    results = @fetcher.fetch(@feed)
    assert_equal 1, results.size, "should filter out the ignored 'Watch:' entry"
    assert_equal "Markets rally on earnings news", results.first[:title]
  end

  test "returns empty array and logs on HTTP error" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    results = @fetcher.fetch(@feed)
    assert_equal [], results
  end
end
