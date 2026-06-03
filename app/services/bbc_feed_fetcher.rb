class BbcFeedFetcher
  ALLOWED_HOSTS = %w[feeds.bbci.co.uk www.bbc.co.uk www.bbc.com].freeze

  def fetch(feed)
    uri = URI.parse(feed.url)
    unless uri.scheme.in?(%w[https http]) && ALLOWED_HOSTS.include?(uri.host)
      raise ArgumentError, "Feed URL #{feed.url.inspect} is not an allowed BBC host"
    end

    xml = HTTParty.get(feed.url, follow_redirects: false).body
    parsed   = Feedjira.parse(xml)
    parsed.entries.filter_map do |entry|
      next if Article.ignorable?(entry.title, entry.url)

      {
        title:        entry.title,
        url:          entry.url,
        description:  entry.summary,
        published_at: entry.published,
        status:       "pending"
      }
    end
  rescue ArgumentError
    raise  # SSRF / allowlist violations must not be silently swallowed
  rescue StandardError => e
    Rails.logger.error "BbcFeedFetcher failed for feed #{feed.id} (#{feed.url}): #{e.message}"
    []
  end
end
