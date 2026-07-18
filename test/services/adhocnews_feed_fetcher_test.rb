require "test_helper"

class AdhocnewsFeedFetcherTest < ActiveSupport::TestCase
  VALID_ATOM = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>RSS Feed von www.ad-hoc-news.de</title>
      <entry>
        <title>DAX legt nach Quartalszahlen zu</title>
        <summary>Ein Wirtschaftsueberblick.</summary>
        <link rel="alternate" type="text/html" href="https://www.ad-hoc-news.de/boerse/news/ueberblick/dax-legt-zu/1" />
        <published>#{Time.current.rfc3339}</published>
        <id>https://www.ad-hoc-news.de/boerse/news/ueberblick/dax-legt-zu/1</id>
      </entry>
      <entry>
        <title>Podcast: eine Folge zum Ueberspringen</title>
        <summary>Ignoriert.</summary>
        <link rel="alternate" type="text/html" href="https://www.ad-hoc-news.de/podcast/2" />
        <published>#{Time.current.rfc3339}</published>
        <id>https://www.ad-hoc-news.de/podcast/2</id>
      </entry>
    </feed>
  XML

  setup do
    @feed    = Feed.new(name: "Boerse", url: "https://www.ad-hoc-news.de/rss/boerse.xml", category: "business", source: "adhocnews")
    @fetcher = AdhocnewsFeedFetcher.new
  end

  test "rejects non-https/http schemes" do
    @feed.url = "ftp://www.ad-hoc-news.de/rss/boerse.xml"
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
    stub_request(:get, @feed.url).to_return(body: VALID_ATOM, headers: { "Content-Type" => "application/atom+xml" })

    results = @fetcher.fetch(@feed)
    assert_equal 1, results.size, "should filter out the ignored 'Podcast:' entry"
    assert_equal "DAX legt nach Quartalszahlen zu", results.first[:title]
  end

  test "returns empty array and logs on HTTP error" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    results = @fetcher.fetch(@feed)
    assert_equal [], results
  end
end
