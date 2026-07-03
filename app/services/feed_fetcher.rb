# Shared RSS-fetching logic for source-specific fetchers (BbcFeedFetcher,
# NytFeedFetcher, ...). Subclasses only declare their own allowed hosts.
class FeedFetcher
  def fetch(feed)
    entries(feed).filter_map do |entry|
      next if Article.ignorable?(entry.title, entry.url)

      entry_attrs(entry)
    end
  rescue ArgumentError
    raise  # SSRF / allowlist violations must not be silently swallowed
  rescue StandardError => e
    log_error(feed, e)
    []
  end

  # Like #fetch, but reports every entry instead of silently dropping ignored
  # ones, so a single-feed admin fetch can explain why an item didn't get in.
  # Never raises: allowlist/HTTP/parse failures come back as `error:` instead.
  def fetch_with_report(feed)
    included = []
    ignored  = []

    entries(feed).each do |entry|
      reason = Article.ignore_reason(entry.title, entry.url)
      if reason
        ignored << { title: entry.title, url: entry.url, reason: reason }
      else
        included << entry_attrs(entry)
      end
    end

    { entries: included, ignored:, error: nil }
  rescue StandardError => e
    log_error(feed, e)
    { entries: [], ignored: [], error: e.message }
  end

  private

  def entries(feed)
    uri = URI.parse(feed.url)
    unless uri.scheme.in?(%w[https http]) && allowed_hosts.include?(uri.host)
      raise ArgumentError, "Feed URL #{feed.url.inspect} is not an allowed #{source_label} host"
    end

    xml = HTTParty.get(feed.url, follow_redirects: false).body
    Feedjira.parse(xml).entries
  end

  def entry_attrs(entry)
    {
      title:        entry.title,
      url:          entry.url,
      description:  entry.summary,
      published_at: entry.published,
      status:       "pending"
    }
  end

  def log_error(feed, e)
    Rails.logger.error "#{self.class.name} failed for feed #{feed.id} (#{feed.url}): #{e.message}"
  end

  def allowed_hosts
    raise NotImplementedError, "#{self.class.name} must define #allowed_hosts"
  end

  def source_label
    self.class.name
  end
end
