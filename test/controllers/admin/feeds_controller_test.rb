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

  test "defaults to showing only enabled feeds" do
    disabled_feed = create_feed(name: "Disabled Feed", url: "https://www.bbc.co.uk/news/disabled.xml", enabled: false)

    get admin_feeds_path
    assert_response :success
    assert_match @feed.name, response.body
    assert_no_match disabled_feed.name, response.body
  end

  test "enabled=all shows both enabled and disabled feeds" do
    disabled_feed = create_feed(name: "Disabled Feed", url: "https://www.bbc.co.uk/news/disabled.xml", enabled: false)

    get admin_feeds_path(enabled: "all")
    assert_response :success
    assert_match @feed.name, response.body
    assert_match disabled_feed.name, response.body
  end

  test "enabled=disabled shows only disabled feeds" do
    disabled_feed = create_feed(name: "Disabled Feed", url: "https://www.bbc.co.uk/news/disabled.xml", enabled: false)

    get admin_feeds_path(enabled: "disabled")
    assert_response :success
    assert_no_match @feed.name, response.body
    assert_match disabled_feed.name, response.body
  end

  test "filters feeds by source" do
    nyt_feed = create_feed(name: "NYT Feed", url: "https://rss.nytimes.com/services/xml/rss/nyt/test.xml", source: "nyt")

    get admin_feeds_path(source: "nyt")
    assert_response :success
    assert_match nyt_feed.name, response.body
    assert_no_match @feed.name, response.body
  end

  test "filters feeds by category" do
    business_feed = create_feed(name: "Business Feed", url: "https://www.bbc.co.uk/news/business.xml", category: "business")

    get admin_feeds_path(category: "business")
    assert_response :success
    assert_match business_feed.name, response.body
    assert_no_match @feed.name, response.body
  end

  test "the edit form offers a disable option plus all 24 hours" do
    get edit_admin_feed_path(@feed)
    assert_response :success
    assert_select "select[name=?]", "feed[fetch_hour]" do
      assert_select "option", count: Feed::FETCH_HOURS.size + 1 # 24 hours + "Disabled"
      assert_select "option[value='']"
      assert_select "option[value='0']", "00:00"
      assert_select "option[value='23']", "23:00"
    end
  end

  test "sets a feed's scheduled fetch hour" do
    patch admin_feed_path(@feed), params: { feed: { name: @feed.name, url: @feed.url, category: @feed.category,
                                                    source: @feed.source, fetch_hour: "8" } }
    assert_response :redirect
    assert_equal 8, @feed.reload.fetch_hour
  end

  test "a blank fetch hour disables the schedule" do
    @feed.update!(fetch_hour: 8)

    patch admin_feed_path(@feed), params: { feed: { name: @feed.name, url: @feed.url, category: @feed.category,
                                                    source: @feed.source, fetch_hour: "" } }
    assert_response :redirect
    assert_nil @feed.reload.fetch_hour
  end

  test "sets the fetch hour inline from the index row" do
    patch schedule_admin_feed_path(@feed), params: { fetch_hour: "8" }
    assert_response :redirect
    assert_equal 8, @feed.reload.fetch_hour
  end

  test "clears the fetch hour inline with a blank value" do
    @feed.update!(fetch_hour: 8)
    patch schedule_admin_feed_path(@feed), params: { fetch_hour: "" }
    assert_response :redirect
    assert_nil @feed.reload.fetch_hour
  end

  test "inline schedule change replaces just the row via turbo stream" do
    patch schedule_admin_feed_path(@feed), params: { fetch_hour: "8" }, as: :turbo_stream
    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_equal 8, @feed.reload.fetch_hour
    assert_match "replace", response.body
    assert_match ActionView::RecordIdentifier.dom_id(@feed), response.body
  end

  test "an out-of-range inline fetch hour leaves the schedule unchanged" do
    @feed.update!(fetch_hour: 8)
    patch schedule_admin_feed_path(@feed), params: { fetch_hour: "99" }
    assert_response :redirect
    assert_equal 8, @feed.reload.fetch_hour
  end

  test "the index row renders an inline schedule selector" do
    get admin_feeds_path
    assert_response :success
    assert_select "form[action=?]", schedule_admin_feed_path(@feed) do
      assert_select "select[name=?]", "fetch_hour" do
        assert_select "option", count: Feed::FETCH_HOURS.size + 1 # 24 hours + "Disabled"
      end
    end
  end

  test "a turbo stream row re-render keeps the feed's posted count" do
    translation = create_translation(rewrite: create_rewrite(article: create_article(feed: @feed)))
    TelegramPost.create!(translation:, telegram_channel: create_channel,
                         status: "posted", posted_at: Time.current)

    patch schedule_admin_feed_path(@feed), params: { fetch_hour: "8" }, as: :turbo_stream
    assert_response :success
    assert_match "100%", response.body
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
    patch toggle_admin_feed_path(@feed, enabled: "all"), as: :turbo_stream
    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_not @feed.reload.enabled
    assert_match "Enable", response.body
    assert_match ActionView::RecordIdentifier.dom_id(@feed), response.body
  end

  test "disabling a feed removes it from the turbo stream when the default (enabled-only) filter is active" do
    assert @feed.enabled
    patch toggle_admin_feed_path(@feed), as: :turbo_stream
    assert_response :success
    assert_not @feed.reload.enabled
    assert_match "remove", response.body
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
