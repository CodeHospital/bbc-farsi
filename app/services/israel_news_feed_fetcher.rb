# The Israeli news catalog (Feed::ISRAELNEWS_FEEDS). Many publishers, one
# source, so — like GermanNewsFeedFetcher — its SSRF allowlist is derived from
# the catalog itself rather than hardcoded.
class IsraelNewsFeedFetcher < FeedFetcher
  ALLOWED_HOSTS = Feed::ISRAELNEWS_FEEDS.values.map { |attrs| URI.parse(attrs[:url]).host }.uniq.freeze

  private

  def allowed_hosts = ALLOWED_HOSTS
  def source_label  = "Israel News"
end
