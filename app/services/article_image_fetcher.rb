# Resolves the main image for an article by reading the `og:image` meta tag
# from its original source page (BBC or NYT). Result is cached (Rails.cache /
# Solid Cache) so the source page is fetched at most once per article, and
# only from allow-listed hosts (SSRF guard). Returns the image URL string, or nil.
#
# No schema change: the image is looked up on demand at render time rather than
# stored on the article.
require "open-uri"

class ArticleImageFetcher
  ALLOWED_HOSTS = %w[www.bbc.com www.bbc.co.uk bbc.com bbc.co.uk www.nytimes.com nytimes.com].freeze
  CACHE_TTL     = 1.week
  READ_LIMIT    = 300_000 # bytes — enough to reach <head> meta tags
  OG_IMAGE_RE   = %r{<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']}i
  OG_IMAGE_ALT  = %r{<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']}i

  # Max source pages fetched concurrently when warming the index.
  MAX_CONCURRENCY = 6

  def self.call(article)
    new(article).call
  end

  # Batch-resolve images for many articles, returning { article_id => url|nil }.
  # Already-cached articles cost nothing; cache misses are fetched concurrently
  # (bounded by MAX_CONCURRENCY) so the index doesn't fetch source pages serially.
  def self.call_many(articles)
    results = {}
    mutex   = Mutex.new

    articles.each_slice(MAX_CONCURRENCY) do |batch|
      batch.map do |article|
        Thread.new do
          url = call(article)
          mutex.synchronize { results[article.id] = url }
        end
      end.each(&:join)
    end

    results
  end

  def initialize(article)
    @article = article
  end

  # Returns the cached image URL, or nil. A resolved miss is cached as "" so we
  # don't refetch a page that has no og:image on every request.
  def call
    cached = Rails.cache.fetch("article_og_image/#{@article.id}", expires_in: CACHE_TTL) do
      fetch_og_image.to_s
    end
    cached.presence
  end

  private

  def fetch_og_image
    uri = URI.parse(@article.url.to_s)
    return unless uri.is_a?(URI::HTTP) && ALLOWED_HOSTS.include?(uri.host)

    html = URI.open(uri.to_s, # rubocop:disable Security/Open
      "User-Agent" => "Mozilla/5.0 (compatible; bbcfarsi/1.0)",
      read_timeout: 8, open_timeout: 5).read(READ_LIMIT)

    html[OG_IMAGE_RE, 1] || html[OG_IMAGE_ALT, 1]
  rescue StandardError => e
    Rails.logger.warn "ArticleImageFetcher failed for article #{@article.id} (#{@article.url}): #{e.message}"
    nil
  end
end
