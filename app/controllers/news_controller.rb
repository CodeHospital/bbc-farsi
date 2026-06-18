# Public-facing news site (no authentication). Magazine layout (Newspaper-style)
# showing the latest completed Persian translation (or refinement) per article.
#
# The site is bilingual: the default Persian (`fa`) edition shows the
# translated/refined text, while the English (`en`) edition shows the *original*
# BBC article (title + description). The edition is chosen by the `lang` query
# param and is propagated across every generated link via `default_url_options`.
class NewsController < ApplicationController
  layout "news"

  LANGUAGES = %w[fa en].freeze

  before_action :set_news_lang
  before_action :load_chrome, only: %i[index show]

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
      return redirect_to(news_path(@translation.seo_param), status: :moved_permanently)
    end

    @article = @translation.article
    @image_url = ArticleImageFetcher.call(@article)
    @tags = TagGenerator.tags_for(@article)
    @sidebar_image_urls = ArticleImageFetcher.call_many(@sidebar_recent.map(&:article))
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

  # Carry the active edition (?lang=en) through every URL helper, so links keep
  # the reader in the same language. Persian is the default and stays unadorned.
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
