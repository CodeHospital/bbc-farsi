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

  # The front page hides stories older than this, unless that would leave it
  # with fewer than FRONT_PAGE_MIN_STORIES, in which case the newest
  # FRONT_PAGE_MIN_STORIES are shown regardless of age.
  FRONT_PAGE_MAX_STORY_AGE = 10.days
  FRONT_PAGE_MIN_STORIES = 10
  # The story bar/viewer only includes news published within this window.
  STORY_WINDOW = 24.hours

  before_action :set_news_lang
  before_action :load_chrome, only: %i[index show search terms privacy]

  # A bad/old slug and an archived (unpublished) translation both raise this —
  # `published_translations`/`Article.not_archived` already exclude archived
  # rows from the lookup scope, so "not found" and "unpublished" collapse into
  # the same case. Rendered in-app (not Rails' generic public/404.html) so it
  # keeps the site's chrome (nav/sidebar/footer), fonts and bilingual copy.
  rescue_from ActiveRecord::RecordNotFound, with: :render_story_not_found

  def index
    stories = if @feed
      @all_stories.select { |s| s.article.feed_id == @feed.id }
    elsif @category
      @all_stories.select { |s| s.article.feed&.category == @category }
    else
      @all_stories
    end
    # A feed's own page lists everything it has published, however old.
    stories = fresh_front_page_stories(stories) unless @feed
    @featured, @rest = posted_first_featured_selection(stories)

    # On the homepage, group the remaining stories into category blocks like a
    # magazine front page; a category page is just a flat list.
    @sections = @category || @feed ? {} : sections_by_category(@rest)

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
      return redirect_to(news_path(id: @translation.seo_param, format: params[:format]),
                         status: :moved_permanently)
    end

    @article = @translation.article
    @image_url = ArticleImageFetcher.call(@article)

    # The article's tags (its feed's tag first, then topic tags), named in the
    # edition's language.
    @tags = TagGenerator.tags_for(@article, language: @news_lang)

    # Markdown twin for LLMs / reader tools: no view tracking or task bumping.
    return render_story_markdown if request.format.symbol == :md

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
      @results = posted_first(portal_search(@query))
      @image_urls = ArticleImageFetcher.call_many(@results.map(&:article))
      SearchQuery.track!(@query, edition: @news_lang, results_count: @results.size)
    else
      @results   = []
      @image_urls = {}
    end
  end

  # GET /terms and /privacy (and /en/…) — static legal pages; the copy lives in
  # app/views/news/{terms,privacy}.html.erb, one block per edition.
  def terms; end
  def privacy; end

  # GET /sitemap.xml — lists the homepage, category pages and every published story.
  def sitemap
    @stories = latest_translation_per_article
    @categories = @stories.filter_map { |story| story.article.feed&.category }.uniq
    respond_to { |format| format.xml }
  end

  # GET /feed(.xml) and /en/feed — RSS 2.0 of the newest stories for the edition.
  def feed
    @stories = story_pool.first(30)
    @image_urls = ArticleImageFetcher.call_many(@stories.map(&:article))
    render formats: :xml, content_type: "application/rss+xml"
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
      Disallow: /edit/
      Disallow: /api

      # AI / LLM crawlers — explicitly welcomed on public content.
      User-agent: GPTBot
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: OAI-SearchBot
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: ChatGPT-User
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: PerplexityBot
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: anthropic-ai
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: Claude-Web
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: Applebot
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: Amazonbot
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: cohere-ai
      Allow: /
      Disallow: /admin
      Disallow: /edit/
      Disallow: /api

      User-agent: CCBot
      Allow: /
      Disallow: /admin
      Disallow: /edit/
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
      # Khabarestan (خبرستان)

      > An automated bilingual news digest that rewrites and translates international world
      > news articles into Persian using large language models, with an English
      > edition for side-by-side reading.

      ## About
      This site ingests English-language international news articles via RSS, rewrites them with an
      LLM, translates the rewrites into Persian (Farsi), and publishes the results
      as a magazine-style news portal. Content is available in both Persian and
      English editions. The project is a demonstration and is not affiliated with
      or endorsed by the original publishers.

      ## What you will find here
      - Persian-language news articles (automatically translated from international news sources)
      - English-language originals (accessible via the /en/ URL prefix)
      - Editable bilingual tags per article (each starts with its source feed's tag)
      - Category sections: #{NewsHelper::CATEGORY_NAMES_EN.values.join(', ')}

      ## Editions and URLs
      - Persian edition (default): #{base}/
      - English edition: #{base}/en/
      - Article pages: #{base}/news/{slug}  (Persian) / #{base}/en/news/{slug} (English)
      - Category pages: #{base}/category/{category}
      - Search: #{base}/search?q={query}

      ## Machine-readable formats
      - Every article page has a clean Markdown twin: append .md to its URL
        (#{base}/news/{slug}.md  /  #{base}/en/news/{slug}.md)
      - RSS feeds: #{base}/feed.xml (Persian), #{base}/en/feed.xml (English)

      ## Latest articles (Persian)
      #{llms_article_links(base, english: false)}

      ## Latest articles (English)
      #{llms_article_links(base, english: true)}

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

  # Markdown list of the newest stories (title + .md link) for /llms.txt.
  def llms_article_links(base, english:)
    prefix = english ? "#{base}/en" : base
    latest_translation_per_article.first(25).map do |story|
      title = english ? (story.article.title.presence || story.translated_title) : story.translated_title
      "- [#{title.to_s.squish.gsub(/[\[\]]/, '')}](#{prefix}/news/#{story.seo_param}.md)"
    end.join("\n")
  end

  # Clean Markdown rendering of one story: title, key facts, body, source link.
  def render_story_markdown
    view         = view_context
    title        = view.story_title(@translation)
    body         = view.story_body(@translation)
    published_at = @article.published_at || @article.created_at
    feed         = @article.feed
    lines = [
      "# #{title}",
      "",
      "- Published: #{published_at&.iso8601}",
      "- Updated: #{@translation.updated_at.iso8601}",
      "- Section: #{view.category_name(feed&.category)}",
      "- Language: #{@news_lang == 'en' ? 'English (en)' : 'Persian (fa)'}",
      "- Source: #{view.source_name(feed)} — #{@article.url}",
      ("- Tags: #{@tags.join(', ')}" if @tags.present?),
      "- Canonical: #{view.news_story_url(@translation)}",
      "",
      body,
      "",
      "---",
      (@news_lang == "en" ? "Original text, summarised by this site." :
                            "ترجمه و بازنویسی خودکار با هوش مصنوعی از منبع اصلی.")
    ].compact
    response.set_header("Link", %(<#{view.news_story_url(@translation)}>; rel="canonical"))
    render plain: lines.join("\n"), content_type: "text/markdown; charset=utf-8"
  end

  # Resolve the requested edition; anything unknown falls back to Persian.
  # Exposed to views/helpers via the `@news_lang` assign.
  def set_news_lang
    @news_lang = LANGUAGES.include?(params[:lang]) ? params[:lang] : "fa"
  end

  # `load_chrome` (nav/sidebar data) has already run by the time any action
  # raises RecordNotFound, so the 404 view renders with the full site chrome.
  def render_story_not_found(exception)
    Sentry.capture_exception(exception)
    render "news/not_found", status: :not_found
  end

  # Shared page chrome: the active category, the full story pool, and the
  # "latest news" sidebar list (with its thumbnails).
  def load_chrome
    @category = params[:category].presence
    @posted_article_ids = posted_article_ids
    @all_stories = posted_first(story_pool)
    @sidebar_recent = @all_stories.first(6)
    posted_stories, unposted_stories = @all_stories.partition { |story| posted_story?(story) }
    @posted_story_pages = fresh_stories_newest_first(posted_stories)
    @story_feeds = story_feed_profiles(unposted_stories)
    @story_image_urls = ArticleImageFetcher.call_many(
      (@posted_story_pages + @story_feeds.flat_map(&:stories)).map(&:article)
    )
    if params[:feed_id].present?
      @feed = Feed.find_by(id: params[:feed_id])
      raise ActiveRecord::RecordNotFound, "feed #{params[:feed_id]}" unless @feed && @all_stories.any? { |story| story.article.feed_id == @feed.id }
    end
    @sidebar_image_urls = ArticleImageFetcher.call_many(@sidebar_recent.map(&:article))
  end

  # Article ids with at least one translation already posted to a Telegram
  # channel. Keyed by article (not translation) so a later refinement of a
  # posted translation still counts as posted.
  def posted_article_ids
    TelegramPost.posted.joins(:translation).distinct.pluck("translations.article_id").to_set
  end

  def posted_story?(story) = @posted_article_ids.include?(story.article_id)

  # Stable partition: stories already posted to Telegram first, then the rest,
  # each half keeping its incoming (newest-first) order.
  def posted_first(stories)
    stories.partition { |story| posted_story?(story) }.flatten(1)
  end

  # Hero selection that keeps posted news above unposted news: featured slots
  # are filled from posted stories first and only topped up with unposted ones
  # when fewer than FeaturedSelector::DEFAULT_LIMIT stories have been posted.
  def posted_first_featured_selection(stories)
    posted_stories, unposted_stories = stories.partition { |story| posted_story?(story) }
    featured_posted, rest_posted = FeaturedSelector.select(posted_stories)
    open_slots = FeaturedSelector::DEFAULT_LIMIT - featured_posted.size
    featured_unposted, rest_unposted =
      open_slots.positive? ? FeaturedSelector.select(unposted_stories, limit: open_slots) : [ [], unposted_stories ]
    [ featured_posted + featured_unposted, rest_posted + rest_unposted ]
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

  FeedProfile = Struct.new(:feed, :stories, :latest_at, keyword_init: true)

  # One "profile" per feed that published in the last STORY_WINDOW, for the
  # story viewer: feeds with the most recent news first, each feed's stories
  # newest first. Older news never appears in the viewer.
  def story_feed_profiles(stories)
    cutoff = STORY_WINDOW.ago
    fresh_stories = stories.select { |story| story_published_at(story) >= cutoff }
    fresh_stories.group_by { |story| story.article.feed }.filter_map do |feed, feed_stories|
      next unless feed

      sorted = feed_stories.sort_by { |story| -story_published_at(story).to_f }
      FeedProfile.new(feed: feed, stories: sorted, latest_at: story_published_at(sorted.first))
    end.sort_by { |profile| -profile.latest_at.to_f }
  end

  def story_published_at(story) = story.article.published_at || story.created_at

  # Stories from the last STORY_WINDOW, newest first, across every feed — the
  # pages of the single "posted on Telegram" story bubble.
  def fresh_stories_newest_first(stories)
    cutoff = STORY_WINDOW.ago
    stories.select { |story| story_published_at(story) >= cutoff }
           .sort_by { |story| -story_published_at(story).to_f }
  end

  # Drop stories older than FRONT_PAGE_MAX_STORY_AGE. If fewer than
  # FRONT_PAGE_MIN_STORIES are that fresh, top up with the next newest instead
  # (`stories` is newest-first, so its head is the fresh ones plus the top-up).
  def fresh_front_page_stories(stories)
    cutoff = FRONT_PAGE_MAX_STORY_AGE.ago
    fresh_stories = stories.select { |story| (story.article.published_at || story.created_at) >= cutoff }
    fresh_stories.size >= FRONT_PAGE_MIN_STORIES ? fresh_stories : stories.first(FRONT_PAGE_MIN_STORIES)
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
    Sentry.capture_exception(error)
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
