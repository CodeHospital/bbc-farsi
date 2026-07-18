require "test_helper"

class Admin::FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @feed = create_feed
    log_in_as
  end

  test "lists feeds" do
    get admin_feeds_path
    assert_response :success
  end

  test "seeds Ad Hoc News feeds" do
    assert_difference("Feed.count", Feed::ADHOCNEWS_FEEDS.size) do
      post seed_admin_feeds_path(source: "adhocnews")
    end
    assert_response :redirect
    assert_equal [ "adhocnews" ], Feed.where(source: "adhocnews").pluck(:source).uniq
  end

  test "toggles feed enabled state" do
    assert @feed.enabled
    patch toggle_admin_feed_path(@feed)
    assert_response :redirect
    assert_not @feed.reload.enabled
  end

  test "toggles feed enabled state via turbo stream without a page redirect" do
    assert @feed.enabled
    patch toggle_admin_feed_path(@feed), as: :turbo_stream
    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_not @feed.reload.enabled
    assert_match "Enable", response.body
    assert_match ActionView::RecordIdentifier.dom_id(@feed), response.body
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

  test "editors are redirected away from feeds (admin-only)" do
    post admin_logout_path
    log_in_as(create_editor_user)

    get admin_feeds_path
    assert_redirected_to admin_root_path
  end
end
