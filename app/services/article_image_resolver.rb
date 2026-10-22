# Background step that gives each article its best lead image, so no visitor
# request ever downloads a source page. Picks articles not yet resolved
# (`image_resolved_at` NULL), newest first, and stores the source page's
# og:image — falling back to the feed image saved at ingestion when the page
# has none or can't be fetched.
#
# Driven by both `bin/rails bbc:resolve_images` (cron/backfill) and the
# in-process poller (BackgroundPollers). They
# can race safely: each article is claimed with a conditional UPDATE on
# `image_resolved_at` before any fetching.
class ArticleImageResolver
  BATCH_SIZE      = 30
  MAX_CONCURRENCY = 6

  # Resolves up to `limit` pending articles. Returns how many this call handled.
  def self.resolve_pending(limit: BATCH_SIZE)
    candidate_ids = Article.where(image_resolved_at: nil).order(id: :desc).limit(limit).pluck(:id)
    claimed_ids   = candidate_ids.select { |article_id| claim(article_id) }
    articles      = Article.where(id: claimed_ids).to_a

    og_image_urls_by_article_id = fetch_og_image_urls(articles)
    articles.each { |article| store(article, og_image_urls_by_article_id[article.id]) }
    articles.size
  end

  # Resolves one article right now (used when posting a story the poller
  # hasn't reached yet). No-op if someone else already claimed it.
  def self.resolve!(article)
    if claim(article.id)
      store(article, og_image_url_for(article))
    else
      article.reload
    end
  end

  # Marks every article whose stored image is still empty as unresolved, so
  # the next runs try their source pages again (e.g. after a publisher outage
  # or an allow-list fix). Returns the number reset.
  def self.reset_missing!
    Article.where(image_url: [ nil, "" ]).where.not(image_resolved_at: nil).update_all(image_resolved_at: nil)
  end

  def self.claim(article_id)
    Article.where(id: article_id, image_resolved_at: nil).update_all(image_resolved_at: Time.current) == 1
  end

  # A value the old render-time lookup already cached saves the HTTP call.
  def self.og_image_url_for(article)
    legacy_cached_value = ArticleImageFetcher.legacy_cached_value(article)
    return legacy_cached_value.presence unless legacy_cached_value.nil?

    ArticleImageFetcher.fetch_from_source(article)
  end

  # HTTP only inside the threads; all DB writes happen back on the caller.
  def self.fetch_og_image_urls(articles)
    og_image_urls_by_article_id = {}
    results_mutex = Mutex.new

    articles.each_slice(MAX_CONCURRENCY) do |article_batch|
      article_batch.map do |article|
        Thread.new do
          og_image_url = og_image_url_for(article)
          results_mutex.synchronize { og_image_urls_by_article_id[article.id] = og_image_url }
        end
      end.each(&:join)
    end

    og_image_urls_by_article_id
  end

  # update_columns: a background image fill isn't an editorial change, so it
  # shouldn't create PaperTrail versions or bump updated_at.
  def self.store(article, og_image_url)
    best_image_url = og_image_url.presence || article.image_url.presence
    article.update_columns(image_url: best_image_url)
    article
  end

  private_class_method :claim, :og_image_url_for, :fetch_og_image_urls, :store
end
