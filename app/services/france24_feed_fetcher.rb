# France 24 (English). Single publisher, so the allowlist is the feed hosts
# from the France 24 catalog (Feed::FRANCE24_FEEDS).
class France24FeedFetcher < FeedFetcher
  private

  def allowed_hosts = %w[www.france24.com]
  def source_label  = "France 24"
end
