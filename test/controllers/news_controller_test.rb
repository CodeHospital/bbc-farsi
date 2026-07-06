require "test_helper"

class NewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Index/show resolve each article's og:image from its source page; stub them
    # all by default so tests don't hit the network. Individual tests override.
    stub_request(:get, /bbc\.(com|co\.uk)/).to_return(body: "<html><head></head></html>")
  end

  test "index lists completed translations without authentication" do
    translation = create_translation(attrs: { translated_title: "تیتر خبر" })

    get root_path

    assert_response :success
    assert_select ".overlay-title, .post-title", /تیتر خبر/
  end

  test "index shows only the latest version per article" do
    rewrite = create_rewrite
    create_translation(rewrite:, attrs: { translated_title: "نسخهٔ قدیمی", created_at: 2.hours.ago })
    create_translation(rewrite:, attrs: { translated_title: "نسخهٔ تازه (refine)", prompt_name: "refine", created_at: 1.hour.ago })

    get root_path

    assert_response :success
    assert_match "نسخهٔ تازه (refine)", @response.body
    assert_no_match "نسخهٔ قدیمی", @response.body
  end

  test "index excludes archived translations and articles" do
    create_translation(attrs: { translated_title: "آرشیو ترجمه", archived: true })
    archived_article = create_article(attrs: { archived: true })
    create_translation(rewrite: create_rewrite(article: archived_article),
      attrs: { translated_title: "آرشیو مقاله" })

    get root_path

    assert_response :success
    assert_no_match "آرشیو ترجمه", @response.body
    assert_no_match "آرشیو مقاله", @response.body
  end

  test "show renders the translated article with its source image" do
    translation = create_translation(attrs: { translated_title: "تیتر کامل", translated_body: "متن کامل خبر" })
    stub_request(:get, translation.article.url)
      .to_return(body: %(<html><head><meta property="og:image" content="https://ichef.bbci.co.uk/x.jpg"></head></html>))

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select "h1", /تیتر کامل/
    assert_select "figure.article-figure img[src=?]", "https://ichef.bbci.co.uk/x.jpg"
  end

  test "show renders without an image when the source has no og:image" do
    translation = create_translation
    stub_request(:get, translation.article.url).to_return(body: "<html><head></head></html>")

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select "figure.article-figure", false
  end

  test "show renders AI tags when the article has cached tags" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    translation = create_translation
    TagGenerator.store(translation.article_id, %w[ایران اقتصاد])

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select ".article-tags .tag-chip", count: 2
    assert_select ".tag-chip", /ایران/
  ensure
    Rails.cache = original
  end

  test "index renders a hero featured card" do
    create_translation(attrs: { translated_title: "خبر ویژه" })

    get root_path

    assert_response :success
    assert_select ".overlay-card.hero"
  end

  test "category page filters stories to that feed category" do
    tech = create_translation(rewrite: create_rewrite(article: create_article(feed: create_feed(category: "technology"))),
      attrs: { translated_title: "خبر فناوری" })
    health = create_translation(rewrite: create_rewrite(article: create_article(feed: create_feed(category: "health"))),
      attrs: { translated_title: "خبر سلامت" })

    get category_path(category: "technology")

    assert_response :success
    # Main column is scoped to the category; the sidebar still lists site-wide news.
    main_html = css_select("main").to_html
    assert_match "خبر فناوری", main_html
    assert_no_match "خبر سلامت", main_html
  end

  # ── Bilingual: /en/ prefix shows the original BBC article ────────────────

  test "index in english edition shows the original title and is ltr" do
    article = create_article(attrs: { title: "Original English Headline" })
    create_translation(rewrite: create_rewrite(article: article), attrs: { translated_title: "تیتر فارسی" })

    get en_root_path

    assert_response :success
    assert_select "html[lang=en][dir=ltr]"
    assert_match "Original English Headline", @response.body
    assert_no_match "تیتر فارسی", @response.body
  end

  test "index defaults to the persian edition" do
    article = create_article(attrs: { title: "Original English Headline" })
    create_translation(rewrite: create_rewrite(article: article), attrs: { translated_title: "تیتر فارسی" })

    get root_path

    assert_response :success
    assert_select "html[lang=fa][dir=rtl]"
    assert_match "تیتر فارسی", @response.body
    assert_no_match "Original English Headline", @response.body
  end

  test "show in english edition renders the original article body in english" do
    article = create_article(attrs: { title: "English Title", description: "English summary body." })
    translation = create_translation(rewrite: create_rewrite(article: article),
      attrs: { translated_title: "تیتر فارسی", translated_body: "متن فارسی" })
    stub_request(:get, article.url).to_return(body: "<html></html>")

    get news_path(id: translation.seo_param, lang: "en")

    assert_response :success
    assert_select "html[lang=en]"
    assert_select "h1", /English Title/
    assert_match "English summary body.", @response.body
    assert_match %r{"inLanguage":\s*"en"}, @response.body
  end

  test "language toggle and hreflang alternates are present" do
    create_translation
    get root_path

    assert_response :success
    # Toggle to the English edition (now /en/ path prefix, not ?lang=en).
    assert_select "link[rel=alternate][hreflang=en]"
    assert_select "link[rel=alternate][hreflang=fa]"
    assert_select "a[href*='/en']"
  end

  # ── English edition surfaces still-untranslated articles ──────────────────

  test "english edition lists untranslated articles; persian edition hides them" do
    create_article(attrs: { title: "Untranslated Breaking News", published_at: 1.hour.ago })

    get en_root_path
    assert_response :success
    assert_match "Untranslated Breaking News", @response.body

    get root_path
    assert_response :success
    assert_no_match "Untranslated Breaking News", @response.body
  end

  test "show resolves an untranslated article story by its a-prefixed param" do
    article = create_article(attrs: { title: "Lone English Story",
      description: "Body of an as-yet untranslated article.", published_at: 1.hour.ago })
    story = ArticleStory.new(article)
    stub_request(:get, article.url).to_return(body: "<html></html>")

    get news_path(id: story.seo_param, lang: "en")

    assert_response :success
    assert_select "h1", /Lone English Story/
    assert_match "Body of an as-yet untranslated article.", @response.body
  end

  # ── SEO: friendly URLs, canonical redirect, meta, structured data ─────────

  test "seo_param produces a pure slug without the numeric id; admin to_param stays numeric" do
    translation = create_translation(attrs: { translated_title: "خبر مهم امروز" })

    assert_equal "خبر-مهم-امروز", translation.seo_param
    assert_equal translation.id.to_s, translation.to_param # admin routes unaffected
    # The public path must not contain a bare numeric id segment before the slug.
    refute_match %r{/news/\d+-}, news_path(id: translation.seo_param)
  end

  test "show redirects a non-canonical slug to the canonical url (301)" do
    translation = create_translation(attrs: { translated_title: "عنوان درست" })
    stub_request(:get, translation.article.url).to_return(body: "<html></html>")

    get "/news/#{translation.id}-wrong-slug"

    assert_response :moved_permanently
    assert_redirected_to news_path(id: translation.seo_param)
  end

  test "show renders the cute not-found page for an unknown slug" do
    get news_path(id: "no-such-story")

    assert_response :not_found
    assert_select "meta[name=robots][content=?]", "noindex, follow"
    assert_match(/پیدا نشد/, @response.body)
  end

  test "show renders the not-found page for an archived (unpublished) translation" do
    translation = create_translation(attrs: { translated_title: "خبر آرشیو شده", archived: true })

    get news_path(id: translation.seo_param)

    assert_response :not_found
    assert_match(/پیدا نشد/, @response.body)
  end

  test "show renders the not-found page in english with home/search links" do
    get news_path(id: "missing", lang: "en")

    assert_response :not_found
    assert_match(/Story not found/, @response.body)
    assert_select "a[href=?]", en_root_path
  end

  test "show emits canonical link, description meta and NewsArticle JSON-LD" do
    translation = create_translation(attrs: { translated_title: "تیتر", translated_body: "متن خبر برای توضیحات" })
    stub_request(:get, translation.article.url).to_return(body: "<html></html>")

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select "link[rel=canonical][href=?]", news_url(id: translation.seo_param)
    assert_select "meta[name=description][content=?]", "متن خبر برای توضیحات"
    assert_select "meta[property='og:type'][content=article]"
    assert_match %r{"@type":\s*"NewsArticle"}, @response.body
  end

  test "sitemap lists the homepage and published stories" do
    translation = create_translation
    stub_request(:get, /bbc/).to_return(body: "<html></html>")

    get sitemap_path

    assert_response :success
    assert_equal "application/xml", @response.media_type
    assert_match news_url(id: translation.seo_param), @response.body
    assert_match root_url, @response.body
  end

  test "robots.txt is served dynamically with the sitemap url" do
    get robots_path

    assert_response :success
    assert_match "User-agent: *", @response.body
    assert_match sitemap_url, @response.body
  end

  # ── Search: URL and result correctness per edition ────────────────────────

  test "farsi search lands on the persian search results page and finds translated content" do
    article = create_article(attrs: { title: "UK Politics" })
    create_translation(rewrite: create_rewrite(article:), attrs: { translated_title: "سیاست بریتانیا" })
    other   = create_article(attrs: { title: "Health news" })
    create_translation(rewrite: create_rewrite(article: other), attrs: { translated_title: "اخبار سلامت" })

    get news_search_path(q: "سیاست")

    assert_response :success
    assert_equal "/search", request.path
    assert_not request.path.start_with?("/en")
    assert_select "html[lang=fa][dir=rtl]"
    main_html = css_select("main").to_html
    assert_match "سیاست بریتانیا", main_html
    assert_no_match "اخبار سلامت", main_html
  end

  test "english search lands on the english search results page and finds source content" do
    article = create_article(attrs: { title: "Climate Summit", published_at: 1.hour.ago })
    create_translation(rewrite: create_rewrite(article:), attrs: { translated_title: "اجلاس آب و هوا" })
    other   = create_article(attrs: { title: "Football results", published_at: 2.hours.ago })
    create_translation(rewrite: create_rewrite(article: other), attrs: { translated_title: "نتایج فوتبال" })

    get news_search_path(lang: "en", q: "climate")

    assert_response :success
    assert_equal "/en/search", request.path
    assert request.path.start_with?("/en")
    assert_select "html[lang=en][dir=ltr]"
    main_html = css_select("main").to_html
    assert_match "Climate Summit", main_html
    assert_no_match "Football results", main_html
    assert_no_match "اجلاس آب و هوا", main_html
  end
end
