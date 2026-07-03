require "test_helper"

class BbcFeedFetcherTest < ActiveSupport::TestCase
  VALID_RSS = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <item>
        <title>UK election update</title>
        <link>https://www.bbc.co.uk/news/uk-123</link>
        <description>A political summary.</description>
        <pubDate>#{Time.current.rfc2822}</pubDate>
      </item>
      <item>
        <title>Watch: something to skip</title>
        <link>https://www.bbc.co.uk/news/watch-456</link>
        <description>Ignored.</description>
        <pubDate>#{Time.current.rfc2822}</pubDate>
      </item>
    </channel></rss>
  XML

  setup do
    @feed    = Feed.new(name: "Tech", url: "https://feeds.bbci.co.uk/news/technology/rss.xml", category: "technology")
    @fetcher = BbcFeedFetcher.new
  end

  test "rejects non-https/http schemes" do
    @feed.url = "ftp://feeds.bbci.co.uk/news/rss.xml"
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
    assert_equal "UK election update", results.first[:title]
  end

  test "returns empty array and logs on HTTP error" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    results = @fetcher.fetch(@feed)
    assert_equal [], results
  end

  test "fetch_with_report includes every entry, tagging ignored ones with a reason" do
    stub_request(:get, @feed.url).to_return(body: VALID_RSS, headers: { "Content-Type" => "application/rss+xml" })

    result = @fetcher.fetch_with_report(@feed)
    assert_nil result[:error]
    assert_equal 1, result[:entries].size
    assert_equal "UK election update", result[:entries].first[:title]
    assert_equal 1, result[:ignored].size
    assert_equal "Watch: something to skip", result[:ignored].first[:title]
    assert_match(/Watch:/, result[:ignored].first[:reason])
  end

  test "fetch_with_report reports disallowed hosts as an error instead of raising" do
    @feed.url = "https://evil.example.com/rss.xml"

    result = @fetcher.fetch_with_report(@feed)
    assert_equal [], result[:entries]
    assert_equal [], result[:ignored]
    assert_match(/not an allowed/, result[:error])
  end

  test "fetch_with_report reports HTTP errors instead of raising" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    result = @fetcher.fetch_with_report(@feed)
    assert_equal [], result[:entries]
    assert_equal [], result[:ignored]
    assert_equal "timeout", result[:error]
  end
end
