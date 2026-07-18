class AdhocnewsFeedFetcher < FeedFetcher
  private

  def allowed_hosts = %w[www.ad-hoc-news.de]
  def source_label  = "Ad Hoc News"
end
