require "test_helper"

class ArticleImageResolverTest < ActiveSupport::TestCase
  OG_IMAGE_URL   = "https://ichef.bbci.co.uk/ace/standard/1024/big.jpg".freeze
  FEED_IMAGE_URL = "https://ichef.bbci.co.uk/ace/standard/240/thumb.jpg".freeze

  def og_page(image_url) = %(<html><head><meta property="og:image" content="#{image_url}"></head></html>)

  test "upgrades the feed image to the source page's og:image and marks it resolved" do
    article = create_article(attrs: { image_url: FEED_IMAGE_URL })
    stub_request(:get, article.url).to_return(body: og_page(OG_IMAGE_URL))

    assert_equal 1, ArticleImageResolver.resolve_pending
    article.reload
    assert_equal OG_IMAGE_URL, article.image_url
    assert_not_nil article.image_resolved_at
  end

  test "keeps the feed image when the page has no og:image or can't be fetched" do
    no_tag_article = create_article(attrs: { image_url: FEED_IMAGE_URL })
    broken_article = create_article(attrs: { image_url: FEED_IMAGE_URL })
    stub_request(:get, no_tag_article.url).to_return(body: "<html><head></head></html>")
    stub_request(:get, broken_article.url).to_return(status: 500)

    ArticleImageResolver.resolve_pending
    assert_equal FEED_IMAGE_URL, no_tag_article.reload.image_url
    assert_equal FEED_IMAGE_URL, broken_article.reload.image_url
    assert_not_nil broken_article.image_resolved_at
  end

  test "resolved articles are not fetched again" do
    article = create_article
    source_page_request = stub_request(:get, article.url).to_return(body: og_page(OG_IMAGE_URL))

    ArticleImageResolver.resolve_pending
    ArticleImageResolver.resolve_pending
    assert_requested source_page_request, times: 1
  end

  test "an article already claimed elsewhere is skipped" do
    article = create_article
    source_page_request = stub_request(:get, article.url)
    article.update_columns(image_resolved_at: Time.current)

    assert_equal 0, ArticleImageResolver.resolve_pending
    assert_not_requested source_page_request
  end

  test "reuses a value cached by the old render-time lookup instead of fetching" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    article = create_article
    Rails.cache.write(format(ArticleImageFetcher::LEGACY_CACHE_KEY, article.id), OG_IMAGE_URL)
    source_page_request = stub_request(:get, article.url)

    ArticleImageResolver.resolve_pending
    assert_equal OG_IMAGE_URL, article.reload.image_url
    assert_not_requested source_page_request
  ensure
    Rails.cache = original_cache
  end

  test "does not create PaperTrail versions" do
    article = create_article
    stub_request(:get, article.url).to_return(body: og_page(OG_IMAGE_URL))
    assert_no_difference(-> { article.versions.count }) { ArticleImageResolver.resolve_pending }
  end

  test "reset_missing! re-queues only articles still without an image" do
    with_image    = create_article(attrs: { image_url: FEED_IMAGE_URL, image_resolved_at: Time.current })
    without_image = create_article(attrs: { image_resolved_at: Time.current })

    assert_equal 1, ArticleImageResolver.reset_missing!
    assert_nil without_image.reload.image_resolved_at
    assert_not_nil with_image.reload.image_resolved_at
  end

  test "ArticleImageFetcher.call reads stored data without HTTP; resolve: true resolves first" do
    article = create_article(attrs: { image_url: FEED_IMAGE_URL })
    source_page_request = stub_request(:get, article.url).to_return(body: og_page(OG_IMAGE_URL))

    assert_equal FEED_IMAGE_URL, ArticleImageFetcher.call(article)
    assert_equal({ article.id => FEED_IMAGE_URL }, ArticleImageFetcher.call_many([ article ]))
    assert_not_requested source_page_request

    assert_equal OG_IMAGE_URL, ArticleImageFetcher.call(article, resolve: true)
    assert_requested source_page_request, times: 1
  end

  test "ingestion stores the feed image on new articles" do
    feed = create_feed(enabled: true)
    entries = [ { title: "Story", url: "https://www.bbc.co.uk/news/img-1", description: "d",
                  published_at: Time.current, image_url: FEED_IMAGE_URL, status: "pending" } ]
    BbcFeedFetcher.stub(:new, Struct.new(:entries) { def fetch(_feed) = entries }.new(entries)) do
      FeedIngestor.ingest_feed(feed, BbcFeedFetcher.new, nil, nil)
    end
    article = Article.find_by!(url: "https://www.bbc.co.uk/news/img-1")
    assert_equal FEED_IMAGE_URL, article.image_url
    assert_nil article.image_resolved_at
  end
end
