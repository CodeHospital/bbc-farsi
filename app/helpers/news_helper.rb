module NewsHelper
  JALALI_MONTH_NAMES_FA = %w[
    فروردین اردیبهشت خرداد تیر مرداد شهریور
    مهر آبان آذر دی بهمن اسفند
  ].freeze

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
      empty_cat:      "خبر دیگری در این دسته نیست.",
      search_placeholder: "جستجو در اخبار…",
      search_label:   "جستجو",
      search_title:   "نتایج جستجو",
      search_results: "نتیجه برای",
      search_empty:   "نتیجه‌ای یافت نشد.",
      switch_label:   "English"
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
      empty_cat:          "No other stories in this category.",
      search_placeholder: "Search news…",
      search_label:       "Search",
      search_title:       "Search results",
      search_results:     "results for",
      search_empty:       "No results found.",
      switch_label:       "فارسی"
    }
  }.freeze

  # ── Edition (language) ──────────────────────────────────────────────────────

  # The active edition; `@news_lang` is set by NewsController#set_news_lang.
  def news_lang = (@news_lang.presence || "fa")
  def english_edition? = news_lang == "en"

  # A UI chrome string for the active edition.
  def news_ui(key) = UI_STRINGS.fetch(news_lang, UI_STRINGS["fa"]).fetch(key)

  # Edition-aware link to the homepage (/ for Farsi, /en for English).
  def home_path = english_edition? ? en_root_path : root_path
  def home_url  = english_edition? ? en_root_url  : root_url

  # Where the language toggle should point: the current page in the other
  # edition, preserving any query params except `lang` (now a URL segment, not
  # a query param).
  def lang_switch_url
    query = request.query_parameters.to_query
    if english_edition?
      # Strip the /en prefix to get the Farsi equivalent path.
      path = request.path.delete_prefix("/en")
      path = "/" if path.blank?
      query.present? ? "#{path}?#{query}" : path
    else
      # Prepend /en to the current path to get the English equivalent.
      path = "/en#{request.path}"
      query.present? ? "#{path}?#{query}" : path
    end
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

  # Friendly public URL for a story. Admin routes keep the plain numeric id.
  def news_story_path(translation) = news_path(id: translation.seo_param)
  def news_story_url(translation)  = news_url(id: translation.seo_param)

  # Fragment-cache key for the sidebar block: a sum of each story's updated_at
  # epoch (cheap, changes whenever any sidebar story changes) plus the total
  # story count so added/removed stories also bust the fragment.
  def news_sidebar_cache_key(sidebar_stories, all_stories_count, lang)
    version_sum = sidebar_stories.sum do |story|
      (story.respond_to?(:updated_at) ? story.updated_at : story.article.updated_at).to_i
    end
    ["news/sidebar", version_sum, all_stories_count, lang]
  end

  # Publication time of a story (article published_at, falling back to creation).
  def story_time(story) = story.article.published_at || story.created_at

  # Convert a Gregorian date to [jy, jm, jd] in the Jalali (Shamsi) calendar.
  # Uses the reference arithmetic algorithm (valid for 1976–2075 CE, sufficient for news).
  def gregorian_to_jalali(gy, gm, gd)
    g_y = gy - 1600
    g_m = gm - 1
    g_d = gd - 1

    g_d_no = (365 * g_y) + ((g_y + 3) / 4) - ((g_y + 99) / 100) + ((g_y + 399) / 400)
    [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ].each_with_index do |days, i|
      break if i >= g_m
      g_d_no += days
    end
    g_d_no += 1 if g_m > 1 && ((g_y % 4 == 0 && g_y % 100 != 0) || g_y % 400 == 0)
    g_d_no += g_d

    j_d_no  = g_d_no - 79
    j_np    = j_d_no / 12053
    j_d_no %= 12053

    jy      = 979 + 33 * j_np + 4 * (j_d_no / 1461)
    j_d_no %= 1461

    if j_d_no >= 366
      jy     += (j_d_no - 1) / 365
      j_d_no  = (j_d_no - 1) % 365
    end

    jm = 0
    [ 31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 ].each_with_index do |days, i|
      break if j_d_no < days
      j_d_no -= days
      jm = i + 1
    end

    [ jy, jm + 1, j_d_no + 1 ]
  end

  # Render an integer using Eastern Arabic (Farsi) digits.
  def to_persian_digits(number)
    number.to_s.tr("0123456789", "۰۱۲۳۴۵۶۷۸۹")
  end

  # Format a Date/Time as a full Jalali date string with Persian digits.
  # e.g. "۲۸ خرداد ۱۴۰۵"
  def jalali_date_string(date_or_time)
    date    = date_or_time.respond_to?(:to_date) ? date_or_time.to_date : date_or_time
    jy, jm, jd = gregorian_to_jalali(date.year, date.month, date.day)
    "#{to_persian_digits(jd)} #{JALALI_MONTH_NAMES_FA[jm - 1]} #{to_persian_digits(jy)}"
  end

  # Short "x ago" style timestamp for a story (Persian or English per edition).
  # Persian edition always shows calendar dates in Jalali with Persian digits.
  def story_timestamp(time)
    return "" unless time

    seconds = (Time.current - time).to_i
    minutes = seconds / 60
    hours   = minutes / 60
    days    = hours / 24

    if english_edition?
      if minutes < 1     then "just now"
      elsif minutes < 60 then "#{minutes} min ago"
      elsif hours < 24   then "#{hours} hr ago"
      elsif days < 7     then "#{days} day#{'s' if days != 1} ago"
      else time.strftime("%d %b %Y")
      end
    else
      if minutes < 1     then "لحظاتی پیش"
      elsif minutes < 60 then "#{to_persian_digits(minutes)} دقیقه پیش"
      elsif hours < 24   then "#{to_persian_digits(hours)} ساعت پیش"
      elsif days < 7     then "#{to_persian_digits(days)} روز پیش"
      else jalali_date_string(time)
      end
    end
  end
end
