# The German regional/national press catalog (Feed::GERMANNEWS_FEEDS). Unlike
# the other fetchers this one serves many publishers, so its SSRF allowlist is
# derived from the catalog itself — a host is reachable only because a feed we
# ship actually lives there, and the two can never drift apart.
class GermanNewsFeedFetcher < FeedFetcher
  ALLOWED_HOSTS = Feed::GERMANNEWS_FEEDS.values.map { |attrs| URI.parse(attrs[:url]).host }.uniq.freeze

  private

  def allowed_hosts = ALLOWED_HOSTS
  def source_label  = "German News"
end
