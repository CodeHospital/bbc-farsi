# Public-facing news site (no authentication). Magazine layout (Newspaper-style)
# showing the latest completed Persian translation (or refinement) per article.
#
# The site is bilingual: the default Persian (`fa`) edition serves URLs at the
# site root (/news/…, /search, …); the English (`en`) edition lives under the
# /en/ prefix (/en/news/…, /en/search, …). The edition is detected from the
# optional :lang URL segment and propagated via `default_url_options`.
class NewsController < ApplicationController
  layout "news"

  LANGUAGES = %w[fa en].freeze

  before_action :set_news_lang
  before_action :load_chrome, only: %i[index show search]

  def index
    stories = @category ? @all_stories.select { |s| s.article.feed&.category == @category } : @all_stories
    @featured, @rest = FeaturedSelector.select(stories)

    # On the homepage, group the remaining stories into category blocks like a
    # magazine front page; a category page is just a flat list.
    @sections = @category ? {} : sections_by_category(@rest)

    @image_urls = ArticleImageFetcher.call_many(
      (@featured + @rest + @sidebar_recent).map(&:article)
    )
  end

  def show
    # An "a"-prefixed id ("a123-slug") is an untranslated article story (shown in
    # the English edition); a digit-prefixed id ("123-slug") is a translation.
    @translation =
      if params[:id].start_with?("a")
        ArticleStory.new(Article.not_archived.find(params[:id].delete_prefix("a").to_i))
      else
        # The :id param is "<id>-<slug>"; .to_i recovers the key (DB-agnostic).
        published_translations.find(params[:id].to_i)
      end

    # Canonical-URL guard: redirect any stale/partial slug to the real one (301)
    # so search engines see a single canonical URL per story.
    if params[:id] != @translation.seo_param
      return redirect_to(news_path(id: @translation.seo_param), status: :moved_permanently)
    end

    @article = @translation.article
    @image_url = ArticleImageFetcher.call(@article)
    @tags = TagGenerator.tags_for(@article)
    @sidebar_image_urls = ArticleImageFetcher.call_many(@sidebar_recent.map(&:article))

    bump_pending_task_priorities(@article)
    ArticleView.track!(article: @article, translation: @translation,
                       edition: @news_lang, request: request)
  end

  # GET /search — full-text search across the portal story pool.
  # Tracks the keyword in search_queries for analytics; gracefully skips
  # tracking when the table has not yet been migrated.
  def search
    @query = params[:q].to_s.strip
    if @query.present?
      @results = portal_search(@query)
      @image_urls = ArticleImageFetcher.call_many(@results.map(&:article))
      SearchQuery.track!(@query, edition: @news_lang, results_count: @results.size)
    else
      @results   = []
      @image_urls = {}
    end
  end

  # GET /sitemap.xml — lists the homepage plus every published story.
  def sitemap
    @stories = latest_translation_per_article
    respond_to { |format| format.xml }
  end

  # GET /robots.txt — served dynamically so the Sitemap directive uses the real
  # request host (the deploy host isn't known at build time).
  def robots
    render plain: "User-agent: *\nAllow: /\nSitemap: #{sitemap_url}\n", content_type: "text/plain"
  end

  # Carry the active edition through every URL helper. Because the routes wrap
  # news paths in `scope "(:lang)"`, passing `lang: "en"` produces /en/… path
  # prefixes rather than ?lang=en query params. Persian is the default and stays
  # at the root (no prefix).
  def default_url_options
    @news_lang == "en" ? { lang: "en" } : {}
  end

  private

  # Resolve the requested edition; anything unknown falls back to Persian.
  # Exposed to views/helpers via the `@news_lang` assign.
  def set_news_lang
    @news_lang = LANGUAGES.include?(params[:lang]) ? params[:lang] : "fa"
  end

  # Shared page chrome: the active category, the full story pool, and the
  # "latest news" sidebar list (with its thumbnails).
  def load_chrome
    @category = params[:category].presence
    @all_stories = story_pool
    @sidebar_recent = @all_stories.first(6)
    @sidebar_image_urls = ArticleImageFetcher.call_many(@sidebar_recent.map(&:article))
  end

  # The story pool driving every page. Persian shows only translated stories;
  # the English edition additionally surfaces still-untranslated articles
  # (wrapped as ArticleStory) so fresh BBC news is visible before the worker
  # pipeline has produced a Persian version. Merged and re-sorted newest-first.
  def story_pool
    stories = latest_translation_per_article
    return stories unless english_edition?

    translated_ids = stories.map(&:article_id)
    extras = untranslated_article_stories(translated_ids)
    (stories + extras)
      .sort_by { |story| story.article.published_at || story.created_at }
      .reverse
  end

  # The active edition (mirrors NewsHelper#english_edition?), available in the
  # controller for shaping the story pool.
  def english_edition? = @news_lang == "en"

  # Recent, non-archived articles that have no completed translation yet,
  # wrapped as ArticleStory. Capped so the homepage's on-demand image fetching
  # and grouping stay bounded.
  def untranslated_article_stories(translated_article_ids, limit: 60)
    Article.not_archived
      .where.not(published_at: nil)
      .where.not(id: translated_article_ids)
      .includes(:feed)
      .order(published_at: :desc)
      .limit(limit)
      .map { |article| ArticleStory.new(article) }
  end

  # Group stories by feed category, preserving the recency order within each and
  # following the canonical category order. Caps each block for a tidy front page.
  def sections_by_category(stories, per_section: 4)
    order = NewsHelper::CATEGORY_NAMES_FA.keys
    stories.group_by { |s| s.article.feed&.category }
           .sort_by { |category, _| order.index(category) || order.size }
           .to_h
           .transform_values { |group| group.first(per_section) }
           .reject { |_category, group| group.empty? }
  end

  # Completed, non-archived translations that actually have Persian text.
  # Refinements are ordinary Translation rows (prompt_name "refine"), so they
  # naturally appear here once completed.
  def published_translations
    Translation.completed
      .where.not(translated_title: [ nil, "" ])
      .where(archived: false)
      .includes(article: :feed)
  end

  # One story per article: the most recently created completed translation,
  # so a finished refinement supersedes the translation it improved.
  #
  # The result drives every page's chrome and is expensive (loads every
  # published translation + its article/feed, then sorts in Ruby), yet only
  # changes when a translation or article row changes. Cache it in
  # Rails.cache (Solid Cache) keyed on a cheap content version so it
  # invalidates the moment the underlying data does (and never serves stale
  # data longer than the short TTL backstop). The pool is language-agnostic —
  # the edition only affects which fields the views read off each story.
  def latest_translation_per_article
    Rails.cache.fetch(story_pool_cache_key, expires_in: 10.minutes) do
      published_translations
        .order(created_at: :desc)
        .group_by(&:article_id)
        .map { |_article_id, versions| versions.first }
        .reject { |translation| translation.article.archived? }
        .sort_by { |translation| translation.article.published_at || translation.created_at }
        .reverse
    end
  end

  # Increment priority on every pending Task tied to this article's rewrites or
  # translations so the worker picks them up sooner when readers click through.
  def bump_pending_task_priorities(article)
    rewrite_tasks     = Task.pending.where(target_type: "Rewrite",     target_id: article.rewrites.select(:id))
    translation_tasks = Task.pending.where(target_type: "Translation", target_id: article.translations.select(:id))
    rewrite_tasks.or(translation_tasks).update_all("priority = priority + 1")
  rescue => error
    Rails.logger.warn("[NewsController] priority bump failed: #{error.message}")
  end

  # Full-text search across the portal story pool (case-insensitive).
  # FA edition searches translated title + body; EN edition searches
  # the original article title + description. Results are capped to 30.
  def portal_search(query)
    like = "%#{query.downcase}%"

    if english_edition?
      Article.not_archived
        .where.not(published_at: nil)
        .includes(:feed)
        .where("LOWER(articles.title) LIKE ? OR LOWER(articles.description) LIKE ?", like, like)
        .order(published_at: :desc)
        .limit(30)
        .map { |article| ArticleStory.new(article) }
    else
      published_translations
        .where("LOWER(translations.translated_title) LIKE ? OR LOWER(translations.translated_body) LIKE ?", like, like)
        .order(created_at: :desc)
        .group_by(&:article_id)
        .map { |_, versions| versions.first }
        .first(30)
    end
  end

  # A content version for the story pool: the newest translation/article
  # timestamps plus the published-translation count. Any new translation,
  # refinement, archive toggle, or article edit moves at least one of these,
  # busting the cache (cheap MAX/COUNT aggregates — no row loading).
  def story_pool_cache_key
    published = Translation.completed.where(archived: false)
    [
      "news/story-pool",
      published.maximum(:updated_at)&.to_f,
      published.count,
      Article.maximum(:updated_at)&.to_f
    ]
  end
end
