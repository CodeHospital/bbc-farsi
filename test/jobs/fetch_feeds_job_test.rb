require "test_helper"

class FetchFeedsJobTest < ActiveJob::TestCase
  setup { @feed = create_feed(enabled: true) }

  test "enqueues RewriteArticleJob for each new article" do
    new_articles = [
      { title: "Story A", url: "https://bbc.co.uk/news/a", description: "d", published_at: Time.current, status: "pending" },
      { title: "Story B", url: "https://bbc.co.uk/news/b", description: "d", published_at: Time.current, status: "pending" }
    ]

    stub_fetcher(returns: new_articles) do
      assert_difference("Article.count", 2) do
        FetchFeedsJob.perform_now
      end
      assert_equal 2, enqueued_jobs.count { |j| j["job_class"] == "RewriteArticleJob" }
    end
  end

  test "skips already-existing articles" do
    existing = create_article(feed: @feed)
    known    = [{ title: existing.title, url: existing.url, description: "d", published_at: Time.current, status: "pending" }]

    stub_fetcher(returns: known) do
      assert_no_difference("Article.count") do
        FetchFeedsJob.perform_now
      end
      assert_empty enqueued_jobs.select { |j| j["job_class"] == "RewriteArticleJob" }
    end
  end

  test "skips disabled feeds" do
    @feed.update!(enabled: false)
    fetched = false

    fake = Object.new
    fake.define_singleton_method(:fetch) { |_feed| fetched = true; [] }
    BbcFeedFetcher.stub(:new, fake) { FetchFeedsJob.perform_now }

    assert_not fetched, "fetcher should not be called for disabled feeds"
  end

  private

  def stub_fetcher(returns:, &block)
    fake = Object.new
    fake.define_singleton_method(:fetch) { |_feed| returns }
    BbcFeedFetcher.stub(:new, fake, &block)
  end
end
