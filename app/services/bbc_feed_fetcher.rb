class BbcFeedFetcher < FeedFetcher
  private

  def allowed_hosts = %w[feeds.bbci.co.uk www.bbc.co.uk www.bbc.com]
  def source_label  = "BBC"
end
