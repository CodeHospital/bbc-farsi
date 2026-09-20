require "test_helper"

class HeiseFeedFetcherTest < ActiveSupport::TestCase
  VALID_ATOM = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>heise online News</title>
      <entry>
        <title>Neue Sicherheitsluecke in weit verbreiteter Bibliothek</title>
        <summary>Ein Ueberblick ueber die Schwachstelle.</summary>
        <link rel="alternate" type="text/html" href="https://www.heise.de/news/sicherheitsluecke-1.html" />
        <published>#{Time.current.rfc3339}</published>
        <id>https://www.heise.de/news/sicherheitsluecke-1.html</id>
      </entry>
      <entry>
        <title>Podcast: eine Folge zum Ueberspringen</title>
        <summary>Ignoriert.</summary>
        <link rel="alternate" type="text/html" href="https://www.heise.de/news/podcast-2.html" />
        <published>#{Time.current.rfc3339}</published>
        <id>https://www.heise.de/news/podcast-2.html</id>
      </entry>
    </feed>
  XML

  setup do
    @feed    = Feed.new(name: "heise online", url: "https://www.heise.de/rss/heise-atom.xml", category: "top", source: "heise")
    @fetcher = HeiseFeedFetcher.new
  end

  test "rejects non-https/http schemes" do
    @feed.url = "ftp://www.heise.de/rss/heise-atom.xml"
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

  test "accepts the sister title Telepolis on its own host" do
    @feed.url = "https://www.telepolis.de/feed.xml"
    stub_request(:get, @feed.url).to_return(body: VALID_ATOM, headers: { "Content-Type" => "application/atom+xml" })

    assert_equal 1, @fetcher.fetch(@feed).size
  end

  test "fetches and parses entries from an allowed host" do
    stub_request(:get, @feed.url).to_return(body: VALID_ATOM, headers: { "Content-Type" => "application/atom+xml" })

    results = @fetcher.fetch(@feed)
    assert_equal 1, results.size, "should filter out the ignored 'Podcast:' entry"
    assert_equal "Neue Sicherheitsluecke in weit verbreiteter Bibliothek", results.first[:title]
  end

  test "returns empty array and logs on HTTP error" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    assert_equal [], @fetcher.fetch(@feed)
  end
end
