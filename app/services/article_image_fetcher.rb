# Lead image for an article.
#
# Reading (`call` / `call_many`) never touches the network: it returns the
# stored `articles.image_url` — the feed's own image, upgraded to the source
# page's og:image by ArticleImageResolver in the background. For articles the
# resolver hasn't reached yet, a value cached by the old render-time lookup
# (Rails.cache) is used if present.
#
# `fetch_from_source` is the one place that downloads the source page to read
# its og:image (allow-listed hosts only — SSRF guard). Only the resolver calls it.
require "open-uri"

class ArticleImageFetcher
  # Hosts ARTICLES live on — not the hosts their feeds live on, which often
  # differ (ZEIT publishes newsfeed.zeit.de but links www.zeit.de). Every
  # German publisher we ship a feed for is included, with and without `www.`,
  # so their stories get a lead image like the BBC/NYT ones do.
  ALLOWED_HOSTS = (
    %w[
      www.bbc.com www.bbc.co.uk bbc.com bbc.co.uk
      www.nytimes.com nytimes.com
      www.ad-hoc-news.de ad-hoc-news.de
      www.heise.de heise.de www.telepolis.de telepolis.de
    ] +
    Feed.all_catalogued_publisher_domains
  ).uniq.freeze
  READ_LIMIT    = 300_000 # bytes — enough to reach <head> meta tags
  OG_IMAGE_RE   = %r{<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']}i
  OG_IMAGE_ALT  = %r{<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']}i

  # Key the old render-time lookup cached results under ("" = known miss).
  LEGACY_CACHE_KEY = "article_og_image/%d".freeze

  # Stored image URL or nil. `resolve: true` (background posting only — never
  # in a visitor's request) first resolves an article the resolver hasn't
  # reached yet, so a fresh story still goes out with its best image.
  def self.call(article, resolve: false)
    ArticleImageResolver.resolve!(article) if resolve && article.image_resolved_at.nil?
    stored_image_url(article)
  end

  # { article_id => url|nil } from stored data — no HTTP, any number of articles.
  def self.call_many(articles)
    articles.to_h { |article| [ article.id, stored_image_url(article) ] }
  end

  def self.stored_image_url(article)
    article.image_url.presence || (legacy_cached_value(article).presence if article.image_resolved_at.nil?)
  end

  # What the old render-time lookup cached for this article: a URL, "" for a
  # known miss, or nil when nothing was cached.
  def self.legacy_cached_value(article)
    Rails.cache.read(format(LEGACY_CACHE_KEY, article.id))
  end

  # Downloads the source page and returns its og:image URL, or nil (no tag,
  # disallowed host, or any network/parse error).
  def self.fetch_from_source(article)
    new(article).fetch_og_image
  end

  def initialize(article)
    @article = article
  end

  def fetch_og_image
    uri = article_uri
    return unless uri.is_a?(URI::HTTP) && ALLOWED_HOSTS.include?(uri.host)

    html = URI.open(uri.to_s, # rubocop:disable Security/Open
      "User-Agent" => "Mozilla/5.0 (compatible; khabarestan/1.0)",
      read_timeout: 8, open_timeout: 5).read(READ_LIMIT)

    html[OG_IMAGE_RE, 1] || html[OG_IMAGE_ALT, 1]
  rescue StandardError => e
    Rails.logger.warn "ArticleImageFetcher failed for article #{@article.id} (#{@article.url}): #{e.message}"
    Sentry.capture_exception(e)
    nil
  end

  private

  # German publishers put umlauts straight in the path (junge Welt's
  # /artikel/…böse-banden.html), which URI.parse rejects as non-ASCII. Escape
  # and retry rather than treating those articles as having no image.
  def article_uri
    URI.parse(@article.url.to_s)
  rescue URI::InvalidURIError
    URI.parse(URI::DEFAULT_PARSER.escape(@article.url.to_s))
  end
end
