require "test_helper"

class Admin::FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
    @feed = create_feed
    log_in
  end

  test "lists feeds" do
    get admin_feeds_path
    assert_response :success
  end

  test "toggles feed enabled state" do
    assert @feed.enabled
    patch toggle_admin_feed_path(@feed)
    assert_response :redirect
    assert_not @feed.reload.enabled
  end

  test "deletes a feed" do
    assert_difference("Feed.count", -1) do
      delete admin_feed_path(@feed)
    end
    assert_response :redirect
  end

  test "fetches a single feed and reports new/updated/skipped counts" do
    stub_request(:get, @feed.url).to_return(
      body: <<~XML, headers: { "Content-Type" => "application/rss+xml" }
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <item>
            <title>Fresh story</title>
            <link>https://www.bbc.co.uk/news/fresh-1</link>
            <description>d</description>
            <pubDate>#{Time.current.rfc2822}</pubDate>
          </item>
          <item>
            <title>Watch: a clip</title>
            <link>https://www.bbc.co.uk/news/watch-1</link>
            <description>d</description>
            <pubDate>#{Time.current.rfc2822}</pubDate>
          </item>
        </channel></rss>
      XML
    )

    assert_difference("Article.count", 1) do
      post fetch_admin_feed_path(@feed)
    end

    assert_response :success
    assert_match "New: 1", response.body
    assert_match "Skipped: 1", response.body
  end

  test "reports a fetch error without failing the page" do
    stub_request(:get, @feed.url).to_raise(StandardError.new("timeout"))

    assert_no_difference("Article.count") do
      post fetch_admin_feed_path(@feed)
    end

    assert_response :success
    assert_match "Fetch failed", response.body
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end
end
