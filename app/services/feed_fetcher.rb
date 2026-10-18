# Shared RSS-fetching logic for source-specific fetchers (BbcFeedFetcher,
# NytFeedFetcher, ...). Subclasses only declare their own allowed hosts.
class FeedFetcher
  def fetch(feed)
    entries(feed).filter_map do |entry|
      next if Article.ignorable?(entry.title, entry.url)

      entry_attrs(entry)
    end
  rescue ArgumentError => e
    Sentry.capture_exception(e)
    raise  # SSRF / allowlist violations must not be silently swallowed
  rescue StandardError => e
    log_error(feed, e)
    Sentry.capture_exception(e)
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
    Sentry.capture_exception(e)
    { entries: [], ignored: [], error: e.message }
  end

  private

  def entries(feed)
    uri = URI.parse(feed.url)
    unless uri.scheme.in?(%w[https http]) && allowed_hosts.include?(uri.host)
      raise ArgumentError, "Feed URL #{feed.url.inspect} is not an allowed #{source_label} host"
    end

    xml = HTTParty.get(feed.url, follow_redirects: false, timeout: 10).body
    Feedjira.parse(xml).entries
  end

  def entry_attrs(entry)
    {
      title:        entry.title,
      url:          entry.url,
      description:  entry.summary,
      published_at: entry.published,
      image_url:    feed_image_url(entry),
      status:       "pending"
    }
  end

  NON_IMAGE_EXTENSIONS = /\.(mp3|m4a|aac|ogg|oga|wav|mp4|m4v|mov|webm|pdf)(\?|#|\z)/i

  # The entry's own image (Feedjira maps media:thumbnail, media:content and
  # enclosure to #image). Stored at ingestion so a story has a picture at
  # once; ArticleImageResolver later upgrades it to the larger og:image.
  # Enclosures can be audio/video (podcasts), so those are ignored.
  def feed_image_url(entry)
    candidate_url = entry.respond_to?(:image) ? entry.image.to_s.strip : ""
    return if candidate_url.empty? || candidate_url.match?(NON_IMAGE_EXTENSIONS)
    return unless URI.parse(candidate_url).is_a?(URI::HTTP)

    candidate_url
  rescue URI::InvalidURIError
    nil
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
