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
    # Resolve the :id segment to a story object. Four formats are handled:
    #   "a-some-title"  — new article-story slug (no numeric id)
    #   "a123"/"a123-…" — old article-story format (backwards compat → redirects)
    #   "123"/"123-…"   — old translation format  (backwards compat → redirects)
    #   "persian-title" — new translation slug    (no numeric id)
    @translation =
      case params[:id]
      when /\Aa-/
        ArticleStory.new(Article.not_archived.find_by!(slug: params[:id].delete_prefix("a-")))
      when /\Aa(\d+)/
        ArticleStory.new(Article.not_archived.find($1.to_i))
      when /\A(\d+)/
        published_translations.find($1.to_i)
      else
        published_translations.find_by!(slug: params[:id])
      end

    # Canonical-URL guard: redirect stale/partial/old slugs to the canonical
    # URL so search engines see a single permanent URL per story.
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
  # request host. Explicitly allows major AI / LLM crawlers and protects
  # private admin + API paths from indexing.
  def robots
    content = <<~ROBOTS
      # All crawlers: public content is fully open; admin/api are private.
      User-agent: *
      Allow: /
      Disallow: /admin
      Disallow: /api

      # AI / LLM crawlers — explicitly welcomed on public content.
      User-agent: GPTBot
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: OAI-SearchBot
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: ChatGPT-User
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: PerplexityBot
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: anthropic-ai
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: Claude-Web
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: Applebot
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: Amazonbot
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: cohere-ai
      Allow: /
      Disallow: /admin
      Disallow: /api

      User-agent: CCBot
      Allow: /
      Disallow: /admin
      Disallow: /api

      Sitemap: #{sitemap_url}
    ROBOTS
    render plain: content, content_type: "text/plain"
  end

  # GET /llms.txt — machine-readable site summary for LLM tools (llmstxt.org).
  # Always in English regardless of edition; intended for AI crawlers and tools.
  def llms
    base = request.base_url
    content = <<~LLMS
      # BBC Persian (بی‌بی‌سی فارسی)

      > An automated bilingual news digest that rewrites and translates BBC world
      > news articles into Persian using large language models, with an English
      > edition for side-by-side reading.

      ## About
      This site ingests BBC English news articles via RSS, rewrites them with an
      LLM, translates the rewrites into Persian (Farsi), and publishes the results
      as a magazine-style news portal. Content is available in both Persian and
      English editions. The project is a demonstration and is not affiliated with
      or endorsed by the BBC.

      ## What you will find here
      - Persian-language news articles (automatically translated from BBC sources)
      - English-language originals (accessible via the /en/ URL prefix)
      - AI-generated topic tags per article
      - Category sections: World, UK, Business, Technology, Science, Health, Breaking

      ## Editions and URLs
      - Persian edition (default): #{base}/
      - English edition: #{base}/en/
      - Article pages: #{base}/news/{slug}  (Persian) / #{base}/en/news/{slug} (English)
      - Category pages: #{base}/category/{category}
      - Search: #{base}/search?q={query}

      ## Content language
      Persian (fa-IR) / English (en-GB) — bilingual, same article corpus

      ## Technical metadata
      - Sitemap: #{sitemap_url(format: :xml)}
      - robots.txt: #{base}/robots.txt
      - Canonical slugs are in the article's language (Persian for fa edition)
      - JSON-LD (NewsArticle, BreadcrumbList, WebSite, Organization) on all pages
      - hreflang alternates on every page linking fa ↔ en editions

      ## Crawling guidance
      Full crawl of public pages is permitted. /admin and /api are private.
      Sitemap lists all published stories with lastmod and hreflang alternates.
    LLMS
    render plain: content, content_type: "text/plain"
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
