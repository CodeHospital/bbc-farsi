module NewsHelper
  CATEGORY_NAMES_FA = {
    "top"        => "خبر فوری",
    "world"      => "جهان",
    "uk"         => "بریتانیا",
    "business"   => "اقتصاد",
    "technology" => "فناوری",
    "science"    => "علم و محیط زیست",
    "health"     => "سلامت"
  }.freeze

  # English labels for the original-language edition, in the same canonical order.
  CATEGORY_NAMES_EN = {
    "top"        => "Breaking",
    "world"      => "World",
    "uk"         => "UK",
    "business"   => "Business",
    "technology" => "Technology",
    "science"    => "Science & Environment",
    "health"     => "Health"
  }.freeze

  # Per-category accent colors — the signature tagDiv "Newspaper" look, where
  # each section/label is colour-coded. Falls back to the global red accent.
  CATEGORY_COLORS = {
    "top"        => "#dd3333",
    "world"      => "#4caf50",
    "uk"         => "#1abc9c",
    "business"   => "#e67e22",
    "technology" => "#2980b9",
    "science"    => "#8e44ad",
    "health"     => "#e84393"
  }.freeze

  # UI chrome strings per edition (kept here rather than in I18n yml so the whole
  # bilingual surface of the public site lives in one place).
  UI_STRINGS = {
    "fa" => {
      site_name:    "بی‌بی‌سی فارسی",
      tagline:      "بازنویسی و ترجمهٔ خودکار اخبار بی‌بی‌سی — نسخهٔ نمایشی.",
      home:         "خانه",
      latest_news:  "آخرین اخبار",
      categories:   "دسته‌بندی‌ها",
      sections:     "دسته‌ها",
      follow:       "دنبال کنید",
      more:         "بیشتر ›",
      tags_label:   "برچسب‌ها:",
      read_source:  "مشاهدهٔ خبر اصلی در bbc.com ↗",
      empty_title:  "هنوز خبری برای نمایش وجود ندارد.",
      empty_body:   "به محض آماده‌شدن ترجمه‌ها، اینجا نمایش داده می‌شوند.",
      empty_cat:    "خبر دیگری در این دسته نیست.",
      switch_label: "English"
    },
    "en" => {
      site_name:    "BBC Persian",
      tagline:      "Automatic rewriting and translation of BBC news — demo edition.",
      home:         "Home",
      latest_news:  "Latest News",
      categories:   "Categories",
      sections:     "Sections",
      follow:       "Follow",
      more:         "More ›",
      tags_label:   "Tags:",
      read_source:  "Read the original on bbc.com ↗",
      empty_title:  "There is no news to show yet.",
      empty_body:   "Stories will appear here as soon as translations are ready.",
      empty_cat:    "No other stories in this category.",
      switch_label: "فارسی"
    }
  }.freeze

  # ── Edition (language) ──────────────────────────────────────────────────────

  # The active edition; `@news_lang` is set by NewsController#set_news_lang.
  def news_lang = (@news_lang.presence || "fa")
  def english_edition? = news_lang == "en"

  # A UI chrome string for the active edition.
  def news_ui(key) = UI_STRINGS.fetch(news_lang, UI_STRINGS["fa"]).fetch(key)

  # Where the language toggle should point: the current page in the other
  # edition, preserving the rest of the query string.
  def lang_switch_url
    target = english_edition? ? "fa" : "en"
    query  = request.query_parameters.except("lang")
    query["lang"] = target if target == "en"
    query.empty? ? request.path : "#{request.path}?#{query.to_query}"
  end

  # ── Edition-aware content accessors ─────────────────────────────────────────
  # In the English edition a "story" displays its original BBC article fields;
  # in Persian it displays the translation/refinement.

  def story_title(story)
    english_edition? ? story.article.title.presence || story.translated_title
                     : story.translated_title
  end

  def story_body(story)
    english_edition? ? story.article.description.to_s
                     : story.translated_body.to_s
  end

  def category_name(category)
    english_edition? ? (CATEGORY_NAMES_EN[category.to_s] || category.to_s)
                     : category_name_fa(category)
  end

  def category_name_fa(category)
    CATEGORY_NAMES_FA[category.to_s] || category.to_s
  end

  # Accent colour for a category (used to colour labels and section headers).
  def category_color(category) = CATEGORY_COLORS[category.to_s] || "#dd3333"

  # Inline `--cat` custom-property style so a card/section adopts its category
  # colour without a per-category CSS class explosion.
  def category_style(category) = "--cat: #{category_color(category)}"

  # [slug, name] pairs in canonical order (localized), for the navigation menu.
  def nav_categories
    names = english_edition? ? CATEGORY_NAMES_EN : CATEGORY_NAMES_FA
    CATEGORY_NAMES_FA.keys.map { |slug| [ slug, names[slug] || slug ] }
  end

  # Friendly public URL for a story (id + Persian slug). Admin routes keep the
  # plain numeric id, so the slug lives here rather than on Translation#to_param.
  def news_story_path(translation) = news_path(translation.seo_param)
  def news_story_url(translation)  = news_url(translation.seo_param)

  # Publication time of a story (article published_at, falling back to creation).
  def story_time(story) = story.article.published_at || story.created_at

  # Short "x ago" style timestamp for a story (Persian or English per edition).
  def story_timestamp(time)
    return "" unless time

    seconds = (Time.current - time).to_i
    minutes = seconds / 60
    hours   = minutes / 60
    days    = hours / 24

    if english_edition?
      if minutes < 1    then "just now"
      elsif minutes < 60 then "#{minutes} min ago"
      elsif hours < 24   then "#{hours} hr ago"
      elsif days < 7     then "#{days} day#{'s' if days != 1} ago"
      else time.strftime("%d %b %Y")
      end
    else
      if minutes < 1    then "لحظاتی پیش"
      elsif minutes < 60 then "#{minutes} دقیقه پیش"
      elsif hours < 24   then "#{hours} ساعت پیش"
      elsif days < 7     then "#{days} روز پیش"
      else l(time.to_date, format: :long) rescue time.strftime("%Y/%m/%d")
      end
    end
  end
end
