class NytFeedFetcher < FeedFetcher
  private

  def allowed_hosts = %w[rss.nytimes.com www.nytimes.com]
  def source_label  = "NYT"
end
