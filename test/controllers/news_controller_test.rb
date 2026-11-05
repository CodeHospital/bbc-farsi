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

  test "show renders the translated article with its stored image" do
    translation = create_translation(attrs: { translated_title: "تیتر کامل", translated_body: "متن کامل خبر" })
    translation.article.update_columns(image_url: "https://ichef.bbci.co.uk/x.jpg", image_resolved_at: Time.current)

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select "h1", /تیتر کامل/
    assert_select "figure.article-figure img[src=?]", "https://ichef.bbci.co.uk/x.jpg"
  end

  test "show renders without an image when the article has none" do
    translation = create_translation

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select "figure.article-figure", false
  end

  test "news pages never fetch the source page for an image" do
    translation = create_translation
    source_page_request = stub_request(:get, translation.article.url)

    get news_path(id: translation.seo_param)
    get root_path

    assert_not_requested source_page_request
  end

  test "show renders the article's tags in the edition's language" do
    translation = create_translation
    TagGenerator.store(translation.article_id, [ { name_fa: "ایران", name_en: "Iran" }, { name_fa: "اقتصاد" } ])

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select ".article-tags .tag-chip", count: 3
    assert_select ".tag-chip", /ایران/

    get news_path(id: ArticleStory.new(translation.article).seo_param, lang: "en")
    assert_select ".article-tags .tag-chip", count: 2 # feed + "Iran"; "اقتصاد" has no English name yet
    assert_select ".tag-chip", /Iran/
  end

  test "the source feed is every story's default tag, linked to the feed page" do
    feed = create_feed(name: "World", name_fa: "جهان", category: "world")
    translation = create_translation(rewrite: create_rewrite(article: create_article(feed:)))

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select ".article-tags .tag-chip", count: 1
    assert_select ".article-tags a.tag-chip.tag-feed[href=?]", channel_path(feed_id: feed.id), text: /جهان/
    assert_select "meta[property='article:tag'][content*=?]", "جهان"

    get news_path(id: translation.seo_param, format: :md)
    assert_match(/- Tags: .*جهان/, @response.body)
  end

  test "a tag equal to the feed tag is not repeated" do
    feed = create_feed(name: "World", name_fa: "جهان", category: "world")
    translation = create_translation(rewrite: create_rewrite(article: create_article(feed:)))
    get news_path(id: translation.seo_param)
    feed_tag = css_select(".article-tags .tag-feed").first.text.strip
    TagGenerator.store(translation.article_id, [ feed_tag, "ایران" ])

    get news_path(id: translation.seo_param)

    assert_select ".article-tags .tag-chip", count: 2
  end

  test "index hides stories older than 10 days when at least 10 fresh ones exist" do
    10.times do |index|
      create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: (index + 1).hours.ago })),
        attrs: { translated_title: "خبر تازه #{index}" })
    end
    create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: 11.days.ago })),
      attrs: { translated_title: "خبر کهنه" })

    get root_path

    assert_response :success
    assert_match "خبر تازه 0", @response.body
    assert_no_match "خبر کهنه", @response.body
  end

  test "index tops up with older stories when fewer than 10 are fresh" do
    create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: 1.hour.ago })),
      attrs: { translated_title: "خبر تازه" })
    create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: 30.days.ago })),
      attrs: { translated_title: "خبر کهنه" })

    get root_path

    assert_response :success
    assert_match "خبر تازه", @response.body
    assert_match "خبر کهنه", @response.body
  end

  test "top bar shows primary categories and tucks the rest into a More dropdown" do
    get root_path

    assert_response :success
    assert_select "nav.mainmenu .menu-list > li > a.menu-link[href=?]", category_path(category: "world")
    assert_select "nav.mainmenu .menu-list > li > a.menu-link[href=?]", category_path(category: "sports"), count: 0
    assert_select "nav.mainmenu .menu-more .menu-dropdown a[href=?]", category_path(category: "sports")
  end

  test "top bar primary categories are the ones with the most news in the last 30 days, busiest first" do
    sports_feed = create_feed(name: "Sports", category: "sports")
    health_feed = create_feed(name: "Health", category: "health")
    old_world_feed = create_feed(name: "World", category: "world")
    3.times do
      create_translation(rewrite: create_rewrite(article: create_article(feed: sports_feed, attrs: { published_at: 2.days.ago })))
    end
    create_translation(rewrite: create_rewrite(article: create_article(feed: health_feed, attrs: { published_at: 3.days.ago })))
    5.times do
      create_translation(rewrite: create_rewrite(article: create_article(feed: old_world_feed, attrs: { published_at: 60.days.ago })))
    end

    get root_path

    assert_select "nav.mainmenu .menu-list > li > a.menu-link[href=?]", category_path(category: "sports")
    assert_select "nav.mainmenu .menu-list > li > a.menu-link[href=?]", category_path(category: "health")
    primary_hrefs = css_select("nav.mainmenu .menu-list > li > a.menu-link").map { |link| link["href"] }
    assert_operator primary_hrefs.index(category_path(category: "sports")), :<, primary_hrefs.index(category_path(category: "health"))
  end

  test "story bar only holds feeds with news from the last 24 hours" do
    feed = create_feed(name: "World", category: "world")
    stale_feed = create_feed(name: "Business", category: "business")
    create_translation(rewrite: create_rewrite(article: create_article(feed:, attrs: { published_at: 2.hours.ago })),
      attrs: { translated_title: "خبر جهان" })
    create_translation(rewrite: create_rewrite(article: create_article(feed: stale_feed, attrs: { published_at: 3.days.ago })),
      attrs: { translated_title: "خبر اقتصاد" })

    get root_path

    assert_select "nav.feed-stories button.feed-story", 1
    assert_select "button.feed-story[data-feed-id=?]", feed.id.to_s
    assert_select "#story-viewer"
    story_data = JSON.parse(css_select("#story-viewer-data").first.text)
    assert_equal [ "خبر جهان" ], story_data.flat_map { |profile| profile["pages"].map { |page| page["title"] } }
  end

  test "story bar shows the feed's Persian name, falling back to its name" do
    named_feed = create_feed(name: "World", name_fa: "جهان", category: "world")
    plain_feed = create_feed(name: "Business", category: "business")
    [ named_feed, plain_feed ].each do |feed|
      create_translation(rewrite: create_rewrite(article: create_article(feed:, attrs: { published_at: 2.hours.ago })))
    end

    get root_path

    assert_select "button.feed-story[data-feed-id=?] .label", named_feed.id.to_s, text: "جهان"
    assert_select "button.feed-story[data-feed-id=?] .label", plain_feed.id.to_s, text: "Business"
    story_data = JSON.parse(css_select("#story-viewer-data").first.text)
    assert_equal [ "Business", "جهان" ], story_data.map { |profile| profile["name"] }.sort
  end

  def post_to_telegram(translation)
    TelegramPost.create!(translation:, telegram_channel: create_channel, status: "posted", posted_at: Time.current)
  end

  test "posted news is listed above newer unposted news" do
    feed = create_feed(name: "World", category: "world")
    posted = create_translation(rewrite: create_rewrite(article: create_article(feed:, attrs: { published_at: 3.days.ago })),
      attrs: { translated_title: "خبر ارسال‌شده" })
    unposted_titles = (1..4).map do |number|
      title = "خبر تازه #{number}"
      create_translation(rewrite: create_rewrite(article: create_article(feed:, attrs: { published_at: number.hours.ago })),
        attrs: { translated_title: title })
      title
    end
    post_to_telegram(posted)

    get category_path(category: "world")

    main_titles = css_select("main .mosaic .overlay-title, main section .post-title a").map { |link| link.text.strip }.uniq
    assert_equal "خبر ارسال‌شده", main_titles.first
    assert_equal unposted_titles.size + 1, main_titles.size

    get news_search_path(q: "خبر")
    search_titles = css_select("main .post-title a").map { |link| link.text.strip }
    assert_equal "خبر ارسال‌شده", search_titles.first
  end

  test "a refinement of a posted translation still counts as posted" do
    article = create_article(attrs: { published_at: 3.days.ago })
    original = create_translation(rewrite: create_rewrite(article:), attrs: { translated_title: "نسخه اول" })
    post_to_telegram(original)
    create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: 1.hour.ago })),
      attrs: { translated_title: "خبر تازه" })
    create_translation(rewrite: original.rewrite, attrs: { translated_title: "نسخه بهتر", prompt_name: "refine" })

    get news_search_path(q: "نسخه")
    assert_equal [ "نسخه بهتر" ], css_select("main .post-title a").map { |link| link.text.strip }
    get root_path
    assert_select "main .mosaic .lead .overlay-title", text: "نسخه بهتر"
  end

  test "posted news is its own story at the start of the story bar" do
    world_feed = create_feed(name: "World", category: "world")
    business_feed = create_feed(name: "Business", category: "business")
    posted_world = create_translation(rewrite: create_rewrite(article: create_article(feed: world_feed, attrs: { published_at: 3.hours.ago })),
      attrs: { translated_title: "خبر ارسال‌شده جهان" })
    posted_business = create_translation(rewrite: create_rewrite(article: create_article(feed: business_feed, attrs: { published_at: 4.hours.ago })),
      attrs: { translated_title: "خبر ارسال‌شده اقتصاد" })
    create_translation(rewrite: create_rewrite(article: create_article(feed: world_feed, attrs: { published_at: 1.hour.ago })),
      attrs: { translated_title: "خبر تازه" })
    TelegramPost.create!(translation: create_translation(
      rewrite: create_rewrite(article: create_article(feed: world_feed, attrs: { published_at: 2.hours.ago })),
      attrs: { translated_title: "خبر لغوشده" }), telegram_channel: create_channel, status: "cancelled")
    [ posted_world, posted_business ].each { |translation| post_to_telegram(translation) }

    get root_path

    assert_select "nav.feed-stories ul", 1
    assert_select "nav.feed-stories button.feed-story", 2
    assert_select "nav.feed-stories li:first-child button.feed-story.posted[data-story-key=posted][data-story-open=?]", "0"
    assert_select "nav.feed-stories button.feed-story[data-feed-id=?][data-story-open=?]", world_feed.id.to_s, "1"
    assert_select "nav.feed-stories button.feed-story[data-feed-id=?]", business_feed.id.to_s, 0
    story_data = JSON.parse(css_select("#story-viewer-data").first.text)
    assert_equal [ "posted", world_feed.id.to_s ], story_data.map { |profile| profile["key"] }
    assert_equal [ [ "خبر ارسال‌شده جهان", "خبر ارسال‌شده اقتصاد" ], [ "خبر تازه", "خبر لغوشده" ] ],
      story_data.map { |profile| profile["pages"].map { |page| page["title"] } }
  end

  test "story bar holds just the posted story when every fresh story was posted" do
    post_to_telegram(create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: 2.hours.ago }))))
    post_to_telegram(create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: 3.days.ago }))))

    get root_path

    assert_select "nav.feed-stories button.feed-story", 1
    assert_select "nav.feed-stories button.feed-story.posted", 1
    story_data = JSON.parse(css_select("#story-viewer-data").first.text)
    assert_equal 1, story_data.first["pages"].size
  end

  test "story bar is absent when nothing was published in the last 24 hours" do
    create_translation(rewrite: create_rewrite(article: create_article(attrs: { published_at: 3.days.ago })))

    get root_path

    assert_select "nav.feed-stories", 0
  end

  test "feed page lists that feed's stories" do
    feed = create_feed(name: "World", category: "world")
    other_feed = create_feed(name: "Business", category: "business")
    create_translation(rewrite: create_rewrite(article: create_article(feed:)), attrs: { translated_title: "خبر جهان" })
    create_translation(rewrite: create_rewrite(article: create_article(feed: other_feed)), attrs: { translated_title: "خبر اقتصاد" })

    get channel_path(feed_id: feed.id)

    assert_response :success
    assert_select "main#main-content", text: /خبر جهان/
    assert_select "main#main-content", text: /خبر اقتصاد/, count: 0
  end

  test "feed page for a feed without stories is not found" do
    feed = create_feed

    get channel_path(feed_id: feed.id)

    assert_response :not_found
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

  test "show reports the RecordNotFound to Sentry" do
    captured = nil
    Sentry.stub(:capture_exception, ->(e) { captured = e }) do
      get news_path(id: "no-such-story")
    end

    assert_response :not_found
    assert_kind_of ActiveRecord::RecordNotFound, captured
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

  test "show emits share links, markdown alternate and enriched JSON-LD" do
    translation = create_translation(attrs: { translated_title: "تیتر", translated_body: "متن خبر" })
    stub_request(:get, translation.article.url).to_return(body: "<html></html>")

    get news_path(id: translation.seo_param)

    assert_response :success
    assert_select "link[rel=alternate][type='text/markdown'][href=?]", news_url(id: translation.seo_param, format: :md)
    assert_select "a.share-btn[href^='https://t.me/share/url']"
    assert_select "meta[property='og:image'][content$='/icon.png']"
    assert_match %r{"speakable"}, @response.body
    assert_match %r{"isBasedOn"}, @response.body
  end

  test "story has a markdown twin" do
    translation = create_translation(attrs: { translated_title: "تیتر مارک‌داون", translated_body: "متن خبر" })

    get news_path(id: translation.seo_param, format: :md)

    assert_response :success
    assert_equal "text/markdown", @response.media_type
    assert_match "# تیتر مارک‌داون", @response.body
    assert_match "متن خبر", @response.body
  end

  test "search results page is noindex" do
    get news_search_path(q: "x")

    assert_select "meta[name=robots][content=?]", "noindex, follow"
  end

  test "rss feed lists stories" do
    translation = create_translation(attrs: { translated_title: "تیتر فید" })

    get news_feed_path

    assert_response :success
    assert_equal "application/rss+xml", @response.media_type
    assert_match "تیتر فید", @response.body
    assert_match news_url(id: translation.seo_param), @response.body
  end

  test "llms.txt links the markdown twins" do
    translation = create_translation(attrs: { translated_title: "تیتر ال‌ال‌ام" })

    get llms_path

    assert_response :success
    assert_match "#{translation.seo_param}.md", @response.body
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
