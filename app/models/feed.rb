class Feed < ApplicationRecord
  has_paper_trail

  has_many :articles, dependent: :destroy
  belongs_to :autopost_telegram_channel, class_name: "TelegramChannel", optional: true,
                                          inverse_of: :autoposting_feeds

  SOURCES = %w[bbc nyt adhocnews heise germannews australianews israelnews].freeze

  # Sources that aggregate many different publishers under one `source`, so
  # publisher metadata (name/domain/home page) can't be derived from `source`
  # alone the way it can for bbc/nyt/adhocnews/heise. See #publisher_info.
  MULTI_PUBLISHER_SOURCES = %w[germannews australianews israelnews].freeze

  # Hour-of-day slots a feed can be scheduled for. nil means "not scheduled",
  # which is the default — a feed is only auto-fetched once given an hour.
  FETCH_HOURS = (0..23).to_a.freeze

  validates :name, presence: true
  validates :url, presence: true, uniqueness: true
  validates :category, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :fetch_hour, inclusion: { in: FETCH_HOURS }, allow_nil: true
  # belongs_to(optional: true) only validates presence-when-required, not that
  # the id actually resolves — without this, a bogus id from the inline picker
  # would hit the raw DB foreign-key constraint (an exception) instead of
  # failing validation gracefully like an out-of-range fetch_hour does.
  validates :autopost_telegram_channel_id, inclusion: { in: ->(_feed) { TelegramChannel.ids } }, allow_nil: true

  scope :enabled, -> { where(enabled: true) }
  scope :scheduled, -> { where.not(fetch_hour: nil) }
  scope :autoposting, -> { where.not(autopost_telegram_channel_id: nil) }

  def title
    "#{name} (#{source.upcase})"
  end

  # Hours are server-local (the sweep compares against Time.now.hour), so no
  # timezone conversion here — 8 means 08:00 on the machine running the app.
  def fetch_schedule_label
    fetch_hour ? format("%02d:00", fetch_hour) : "Disabled"
  end

  def autopost_channel_label
    autopost_telegram_channel&.name || "Disabled"
  end

  # Whether Autoposter should actually deliver this feed's translations to its
  # chosen channel — the channel must still be enabled AND have its own
  # Autopost toggle on (deliberately a second gate: the feed says WHERE, the
  # channel says whether it's currently accepting any autoposted content at
  # all, e.g. to pause every feed's autopost to a channel without editing
  # every feed). See Autoposter.
  def autoposts?
    autopost_telegram_channel.present? && autopost_telegram_channel.enabled? && autopost_telegram_channel.autopost?
  end

  def multi_publisher_source? = MULTI_PUBLISHER_SOURCES.include?(source)

  # Publisher name/domain/home page for THIS feed, for sources that mix many
  # publishers — nil for single-publisher sources (bbc/nyt/adhocnews/heise),
  # where NewsHelper::SOURCE_INFO already answers by `source`. A feed an admin
  # added by hand won't be in the catalog, so fall back to its own host.
  def publisher_info
    return nil unless multi_publisher_source?

    self.class.const_get("#{source.upcase}_PUBLISHERS")[url] || derived_publisher_info
  end

  BBC_FEEDS = {
    "Top News"   => { url: "https://feeds.bbci.co.uk/news/rss.xml",                          category: "top" },
    "World"      => { url: "https://feeds.bbci.co.uk/news/world/rss.xml",                    category: "world" },
    "UK"         => { url: "https://feeds.bbci.co.uk/news/uk/rss.xml",                       category: "uk" },
    "Business"   => { url: "https://feeds.bbci.co.uk/news/business/rss.xml",                 category: "business" },
    "Technology" => { url: "https://feeds.bbci.co.uk/news/technology/rss.xml",               category: "technology" },
    "Science"    => { url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",  category: "science" },
    "Health"     => { url: "https://feeds.bbci.co.uk/news/health/rss.xml",                   category: "health" }
  }.freeze

  # The full feed catalog from https://www.nytimes.com/rss (as of 2026-07-03).
  # "Environment" (Science section) and "Climate" (Climate & Weather section)
  # are the same feed on nytimes.com; kept once here as "Climate" since a
  # second entry with the same url would just no-op in seed_feeds!.
  NYT_FEEDS = {
    "Top Stories" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", category: "top" },

    "World"        => { url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml",      category: "world" },
    "Africa"       => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Africa.xml",     category: "world" },
    "Americas"     => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Americas.xml",   category: "world" },
    "Asia Pacific" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/AsiaPacific.xml", category: "world" },
    "Europe"       => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Europe.xml",     category: "world" },
    "Middle East"  => { url: "https://rss.nytimes.com/services/xml/rss/nyt/MiddleEast.xml", category: "world" },

    "U.S."       => { url: "https://rss.nytimes.com/services/xml/rss/nyt/US.xml",        category: "us" },
    "Education"  => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Education.xml", category: "education" },
    "Politics"   => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml",  category: "politics" },
    "The Upshot" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Upshot.xml",    category: "politics" },

    "N.Y./Region" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/NYRegion.xml", category: "nyregion" },

    "Business"             => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Business.xml",            category: "business" },
    "Energy & Environment" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/EnergyEnvironment.xml",   category: "business" },
    "Small Business"       => { url: "https://rss.nytimes.com/services/xml/rss/nyt/SmallBusiness.xml",       category: "business" },
    "Economy"              => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Economy.xml",             category: "business" },
    "DealBook"             => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Dealbook.xml",            category: "business" },
    "Media & Advertising"  => { url: "https://rss.nytimes.com/services/xml/rss/nyt/MediaandAdvertising.xml", category: "business" },
    "Your Money"           => { url: "https://rss.nytimes.com/services/xml/rss/nyt/YourMoney.xml",           category: "business" },

    "Technology"    => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml",  category: "technology" },
    "Personal Tech" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/PersonalTech.xml", category: "technology" },

    "Sports"             => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Sports.xml",            category: "sports" },
    "Baseball"           => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Baseball.xml",          category: "sports" },
    "College Basketball" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/CollegeBasketball.xml", category: "sports" },
    "College Football"   => { url: "https://rss.nytimes.com/services/xml/rss/nyt/CollegeFootball.xml",   category: "sports" },
    "Golf"               => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Golf.xml",              category: "sports" },
    "Hockey"             => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Hockey.xml",            category: "sports" },
    "Pro Basketball"     => { url: "https://rss.nytimes.com/services/xml/rss/nyt/ProBasketball.xml",     category: "sports" },
    "Pro Football"       => { url: "https://rss.nytimes.com/services/xml/rss/nyt/ProFootball.xml",       category: "sports" },
    "Soccer"             => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Soccer.xml",            category: "sports" },
    "Tennis"             => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Tennis.xml",            category: "sports" },

    "Science"        => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml", category: "science" },
    "Space & Cosmos" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Space.xml",    category: "science" },
    "Health"         => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Health.xml",   category: "health" },
    "Well Blog"      => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Well.xml",     category: "health" },
    "Climate"        => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Climate.xml",  category: "climate" },
    "Weather"        => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Weather.xml",  category: "climate" },

    "Arts"         => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Arts.xml",        category: "arts" },
    "Art & Design" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/ArtandDesign.xml", category: "arts" },
    "Book Review"  => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Books/Review.xml", category: "arts" },
    "Dance"        => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Dance.xml",        category: "arts" },
    "Movies"       => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Movies.xml",       category: "arts" },
    "Music"        => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Music.xml",        category: "arts" },
    "Television"   => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Television.xml",   category: "arts" },
    "Theater"      => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Theater.xml",      category: "arts" },
    "Lens Blog"    => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Lens.xml",          category: "arts" },

    "Fashion & Style" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/FashionandStyle.xml", category: "style" },
    "Dining & Wine"   => { url: "https://rss.nytimes.com/services/xml/rss/nyt/DiningandWine.xml",   category: "style" },
    "Love"            => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Weddings.xml",        category: "style" },
    "T Magazine"      => { url: "https://rss.nytimes.com/services/xml/rss/nyt/tmagazine.xml",       category: "style" },
    # Canonical host — the www.nytimes.com link shown on the /rss page 301s here.
    "Travel"          => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Travel.xml",          category: "travel" },

    "Jobs"        => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Jobs.xml",        category: "jobs" },
    "Real Estate" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/RealEstate.xml",  category: "realestate" },
    "Autos"       => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Automobiles.xml", category: "autos" },

    "Obituaries"    => { url: "https://rss.nytimes.com/services/xml/rss/nyt/Obituaries.xml",  category: "obituaries" },
    "Times Wire"    => { url: "https://rss.nytimes.com/services/xml/rss/nyt/recent.xml",      category: "wire" },
    "Most E-Mailed" => { url: "https://rss.nytimes.com/services/xml/rss/nyt/MostEmailed.xml", category: "trending" },
    "Most Shared"   => { url: "https://rss.nytimes.com/services/xml/rss/nyt/MostShared.xml",  category: "trending" },
    "Most Viewed"   => { url: "https://rss.nytimes.com/services/xml/rss/nyt/MostViewed.xml",  category: "trending" },

    "Charles M. Blow"     => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/charles-m-blow/rss.xml",     category: "opinion" },
    "Jamelle Bouie"       => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/jamelle-bouie/rss.xml",      category: "opinion" },
    "David Brooks"        => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/david-brooks/rss.xml",       category: "opinion" },
    "Frank Bruni"         => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/frank-bruni/rss.xml",        category: "opinion" },
    "Gail Collins"        => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/gail-collins/rss.xml",       category: "opinion" },
    "Ross Douthat"        => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/ross-douthat/rss.xml",       category: "opinion" },
    "Maureen Dowd"        => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/maureen-dowd/rss.xml",       category: "opinion" },
    "Thomas L. Friedman"  => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/thomas-l-friedman/rss.xml",  category: "opinion" },
    "Michelle Goldberg"   => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/michelle-goldberg/rss.xml",  category: "opinion" },
    "Ezra Klein"          => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/ezra-klein/rss.xml",         category: "opinion" },
    "Nicholas D. Kristof" => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/nicholas-kristof/rss.xml",   category: "opinion" },
    "Paul Krugman"        => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/paul-krugman/rss.xml",       category: "opinion" },
    "Farhad Manjoo"       => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/farhad-manjoo/rss.xml",      category: "opinion" },
    "Bret Stephens"       => { url: "https://www.nytimes.com/svc/collections/v1/publish/www.nytimes.com/column/bret-stephens/rss.xml",      category: "opinion" },
    "Sunday Opinion"      => { url: "https://rss.nytimes.com/services/xml/rss/nyt/sunday-review.xml",                                       category: "opinion" }
  }.freeze

  # The German-language feed catalog from https://www.ad-hoc-news.de/rss
  # (as of 2026-07-18). Categories reuse the existing canonical set where a
  # good fit exists; "police" is new (same precedent as NYT's extra topical
  # sections that aren't in the nav menu either).
  ADHOCNEWS_FEEDS = {
    "All News"       => { url: "https://www.ad-hoc-news.de/rss/nachrichten.xml",              category: "top" },
    "Ad Hoc Notices" => { url: "https://www.ad-hoc-news.de/rss/adhocnews.xml",                 category: "business" },
    "Stock Market"   => { url: "https://www.ad-hoc-news.de/rss/boerse.xml",                    category: "business" },
    "Economy"        => { url: "https://www.ad-hoc-news.de/rss/wirtschaft.xml",                category: "business" },
    "Politics"       => { url: "https://www.ad-hoc-news.de/rss/politik.xml",                   category: "politics" },
    "Sports"         => { url: "https://www.ad-hoc-news.de/rss/sport.xml",                     category: "sports" },
    "Entertainment"  => { url: "https://www.ad-hoc-news.de/rss/unterhaltung.xml",               category: "arts" },
    "Science"        => { url: "https://www.ad-hoc-news.de/rss/wissenschaft.xml",              category: "science" },
    "Company News"   => { url: "https://www.ad-hoc-news.de/rss/unternehmensnachrichten.xml",   category: "business" },
    "Police Reports" => { url: "https://www.ad-hoc-news.de/rss/polizeimeldungen.xml",          category: "police" },
    "International"  => { url: "https://www.ad-hoc-news.de/rss/ausland.xml",                   category: "world" },
    "Corporate News" => { url: "https://www.ad-hoc-news.de/rss/corporate-news.xml",            category: "business" }
  }.freeze

  # The heise.de feed catalog from https://www.heise.de/news-extern/news.html
  # (the "Übersicht unserer Feeds" page, as of 2026-09-20). All of these are
  # Atom, which Feedjira parses through the same interface as the BBC/NYT RSS.
  # Telepolis is a heise-medien title and lives on its own host; TechStage's
  # old techstage.de/rss.xml now redirects into heise.de/bestenlisten.feed, so
  # the canonical heise.de URL is used here (FeedFetcher never follows
  # redirects, so only canonical URLs work).
  HEISE_FEEDS = {
    "heise online"        => { url: "https://www.heise.de/rss/heise-atom.xml",                     category: "top" },
    "Top-News"            => { url: "https://www.heise.de/rss/heise-top-atom.xml",                 category: "top" },
    "IT"                  => { url: "https://www.heise.de/rss/heise-Rubrik-IT-atom.xml",           category: "technology" },
    "Mobiles"             => { url: "https://www.heise.de/rss/heise-Rubrik-Mobiles-atom.xml",      category: "technology" },
    "Netzpolitik"         => { url: "https://www.heise.de/rss/heise-Rubrik-Netzpolitik-atom.xml",  category: "politics" },
    "Wirtschaft"          => { url: "https://www.heise.de/rss/heise-Rubrik-Wirtschaft-atom.xml",   category: "business" },
    "Wissen"              => { url: "https://www.heise.de/rss/heise-Rubrik-Wissen-atom.xml",       category: "science" },
    "Entertainment"       => { url: "https://www.heise.de/rss/heise-Rubrik-Entertainment-atom.xml", category: "arts" },
    "Journal"             => { url: "https://www.heise.de/rss/heise-Rubrik-Journal-atom.xml",      category: "opinion" },
    "heise Security"      => { url: "https://www.heise.de/security/feed.xml",                      category: "technology" },
    "Security Alerts"     => { url: "https://www.heise.de/security/Alerts/feed.xml",               category: "technology" },
    "heise Developer"     => { url: "https://www.heise.de/developer/feed.xml",                     category: "technology" },
    "heise Download"      => { url: "https://www.heise.de/download/feed/top",                      category: "technology" },
    "tipps+tricks"        => { url: "https://www.heise.de/tipps-tricks/feed.xml",                  category: "technology" },
    "heise Autos"         => { url: "https://www.heise.de/autos/feed.xml",                         category: "autos" },
    "c't Magazin"         => { url: "https://www.heise.de/ct/feed.xml",                            category: "technology" },
    "c't Fotografie"      => { url: "https://www.heise.de/foto/feed.xml",                          category: "technology" },
    "iX Magazin"          => { url: "https://www.heise.de/ix/feed.xml",                            category: "technology" },
    "Mac & i"             => { url: "https://www.heise.de/mac-and-i/feed.xml",                     category: "technology" },
    "Make Magazin"        => { url: "https://www.heise.de/make/feed.xml",                          category: "technology" },
    "TechStage"           => { url: "https://www.heise.de/bestenlisten.feed",                      category: "technology" },
    "Telepolis"           => { url: "https://www.telepolis.de/feed.xml",                           category: "politics" }
  }.freeze

  # Builds a { feed_url => { name:, domain:, url: } } publisher index for a
  # multi-publisher catalog (see MULTI_PUBLISHER_SOURCES). Each entry's key is
  # its Feed#name and doubles as its publisher's display name, unless the
  # entry overrides that with `publisher:` — needed once a catalog holds
  # several feeds from the *same* publisher (e.g. "tagesschau – Ausland" and
  # "tagesschau – Wirtschaft" both attribute to publisher "tagesschau", not to
  # their own section-qualified feed names).
  def self.build_publisher_index(catalog)
    catalog.to_h { |feed_name, attrs|
      publisher_name = attrs[:publisher] || feed_name
      [ attrs[:url], { name: publisher_name, domain: URI.parse(attrs[:site]).host.to_s.delete_prefix("www."), url: attrs[:site] } ]
    }
  end

  # The German-language news catalog from https://rss.feedspot.com/german_news_rss_feeds/
  # (as of 2026-09-20) plus the public-broadcaster feeds from
  # https://www.tagesschau.de/infoservices/rssfeeds, https://www.swr.de,
  # https://www.br.de/service/br-rss-feeds-100.html,
  # https://www1.wdr.de/global/feeds100.html, and
  # https://www.ndr.de/service/.../rssndr101.html (as of 2026-09-20). Unlike
  # every other catalog here, each entry is a *different* publisher, so each
  # one carries the `site:` its articles live on — that's what
  # GERMANNEWS_PUBLISHERS turns into per-feed attribution on the public portal
  # (see #publisher_info).
  #
  # Feedspot lists 57 outlets; these are the ones that actually serve a usable
  # feed at a canonical URL. Left out, with the reason each was rejected when
  # every URL was fetched on 2026-09-20:
  #   - 21 entries (WELT, DW, Tagesspiegel, BILD, …) have no RSS feed on
  #     Feedspot at all — they are "Generate RSS" scraper entries.
  #   - General-Anzeiger + Rheinische Post: HTTP 402 (paywalled feed).
  #   - Main-Post: HTTP 410 Gone. German Brief: connection times out.
  #   - MunichNOW: /feed/ 301s to the homepage. Handelsblatt: only reachable
  #     through an internal infrastructure host, not a stable public URL.
  #   - The Local Germany: entry <link>s contain newlines, so every article
  #     URL would be unusable.
  #   - The Munich Eye: sitemap.rss is a whole-site sitemap (4 500+ entries),
  #     not a news feed — one fetch would enqueue thousands of rewrite tasks.
  GERMANNEWS_FEEDS = {
    "tagesschau"              => { url: "https://www.tagesschau.de/infoservices/alle-meldungen-100~rss2.xml",           category: "top",      site: "https://www.tagesschau.de" },
    "ZEIT ONLINE"             => { url: "https://newsfeed.zeit.de/index",                                                category: "top",      site: "https://www.zeit.de" },
    "DER SPIEGEL"             => { url: "https://www.spiegel.de/international/index.rss",                                category: "top",      site: "https://www.spiegel.de" },
    "Süddeutsche Zeitung"     => { url: "https://rss.sueddeutsche.de/rss/Topthemen",                                     category: "top",      site: "https://www.sueddeutsche.de" },
    "Frankfurter Allgemeine"  => { url: "https://www.faz.net/rss/aktuell/",                                              category: "top",      site: "https://www.faz.net" },
    "FOCUS online"            => { url: "https://www.focus.de/rss",                                                      category: "top",      site: "https://www.focus.de" },
    "Stern"                   => { url: "https://www.stern.de/feed/standard/alle-nachrichten/",                          category: "top",      site: "https://www.stern.de" },
    "t-online"                => { url: "https://www.t-online.de/feed.rss",                                              category: "top",      site: "https://www.t-online.de" },
    "taz"                     => { url: "https://taz.de/!p4608;rss/",                                                    category: "top",      site: "https://taz.de" },
    "deutschland.de"          => { url: "https://www.deutschland.de/en/feed-news/rss.xml",                               category: "top",      site: "https://www.deutschland.de" },
    "Squirrel News"           => { url: "https://squirrel-news.net/feed/",                                               category: "top",      site: "https://squirrel-news.net" },

    "junge Welt"              => { url: "https://www.jungewelt.de/feeds/newsticker.rss",                                 category: "politics", site: "https://www.jungewelt.de" },
    "neues deutschland"       => { url: "https://www.nd-aktuell.de/rss/aktuell.php",                                     category: "politics", site: "https://www.nd-aktuell.de" },
    "JUNGE FREIHEIT"          => { url: "https://jungefreiheit.de/feed/",                                                category: "politics", site: "https://jungefreiheit.de" },

    "Kölner Stadt-Anzeiger"   => { url: "https://feed.ksta.de/feed/rss/index.rss",                                       category: "local",    site: "https://www.ksta.de" },
    "Hamburger Morgenpost"    => { url: "https://www.mopo.de/index?lab_viewport=rss",                                    category: "local",    site: "https://www.mopo.de" },
    "Abendzeitung München"    => { url: "https://www.abendzeitung-muenchen.de/storage/rss/rss/alle-artikel-abendzeitung.xml", category: "local", site: "https://www.abendzeitung-muenchen.de" },
    "Kieler Nachrichten"      => { url: "https://www.kn-online.de/arc/outboundfeeds/rss/",                               category: "local",    site: "https://www.kn-online.de" },
    "Hannoversche Allgemeine" => { url: "https://www.haz.de/arc/outboundfeeds/rss/",                                     category: "local",    site: "https://www.haz.de" },
    "Lübecker Nachrichten"    => { url: "https://www.ln-online.de/arc/outboundfeeds/rss/",                               category: "local",    site: "https://www.ln-online.de" },
    "Ostsee Zeitung"          => { url: "https://www.ostsee-zeitung.de/arc/outboundfeeds/rss/",                          category: "local",    site: "https://www.ostsee-zeitung.de" },
    "Oberhessische Presse"    => { url: "https://www.op-marburg.de/arc/outboundfeeds/rss/",                              category: "local",    site: "https://www.op-marburg.de" },
    "LVZ"                     => { url: "https://www.lvz.de/arc/outboundfeeds/rss/",                                     category: "local",    site: "https://www.lvz.de" },
    "Münstersche Zeitung"     => { url: "https://www.muensterschezeitung.de/rss/feed/mz_lokales",                        category: "local",    site: "https://www.muensterschezeitung.de" },
    "Ruhr Nachrichten"        => { url: "https://www.ruhrnachrichten.de/feed/",                                          category: "local",    site: "https://www.ruhrnachrichten.de" },
    "Aachener Zeitung"        => { url: "https://www.aachener-zeitung.de/rss/",                                          category: "local",    site: "https://www.aachener-zeitung.de" },
    "Freie Presse"            => { url: "https://www.freiepresse.de/chemnitz/feed.atom",                                 category: "local",    site: "https://www.freiepresse.de" },
    "Stuttgart Journal"       => { url: "https://stuttgart-journal.de/tp3/feed/",                                        category: "local",    site: "https://stuttgart-journal.de" },

    # Public-broadcaster feeds. Several sections per broadcaster, so each uses
    # `publisher:` to attribute back to the broadcaster itself rather than to
    # its section-qualified feed name (see .build_publisher_index above).
    "tagesschau – Inland"       => { url: "https://www.tagesschau.de/inland/index~rss2.xml",          category: "politics", site: "https://www.tagesschau.de", publisher: "tagesschau" },
    "tagesschau – Ausland"      => { url: "https://www.tagesschau.de/ausland/index~rss2.xml",         category: "world",    site: "https://www.tagesschau.de", publisher: "tagesschau" },
    "tagesschau – Wirtschaft"   => { url: "https://www.tagesschau.de/wirtschaft/index~rss2.xml",      category: "business", site: "https://www.tagesschau.de", publisher: "tagesschau" },
    "tagesschau – Wissen"       => { url: "https://www.tagesschau.de/wissen/index~rss2.xml",          category: "science",  site: "https://www.tagesschau.de", publisher: "tagesschau" },
    "tagesschau – Investigativ" => { url: "https://www.tagesschau.de/investigativ/index~rss2.xml",    category: "top",      site: "https://www.tagesschau.de", publisher: "tagesschau" },
    "tagesschau – Faktenfinder" => { url: "https://www.tagesschau.de/faktenfinder/index~rss2.xml",    category: "opinion",  site: "https://www.tagesschau.de", publisher: "tagesschau" },
    "tagesschau – Regional"     => { url: "https://www.tagesschau.de/inland/regional/index~rss2.xml", category: "local",    site: "https://www.tagesschau.de", publisher: "tagesschau" },

    "SWR Aktuell" => { url: "https://www.swr.de/~rss/swraktuell/index.xml", category: "local", site: "https://www.swr.de", publisher: "SWR" },

    "BR24 Nachrichten" => { url: "https://www.br.de/nachrichten/meldungen/nachrichten-bayerischer-rundfunk100~newsRss.xml", category: "local", site: "https://www.br.de", publisher: "BR" },

    "WDR – Übersicht"       => { url: "https://www1.wdr.de/uebersicht-100.feed",                                              category: "local",   site: "https://www1.wdr.de", publisher: "WDR" },
    "WDR – Rheinland"       => { url: "https://www1.wdr.de/nrw/rheinland/uebersicht-rheinland-100.feed",                      category: "local",   site: "https://www1.wdr.de", publisher: "WDR" },
    "WDR – Ruhrgebiet"      => { url: "https://www1.wdr.de/nrw/ruhrgebiet/uebersicht-ruhrgebiet-100.feed",                    category: "local",   site: "https://www1.wdr.de", publisher: "WDR" },
    "WDR – Westfalen-Lippe" => { url: "https://www1.wdr.de/nrw/ostwestfalen-lippe/uebersicht-westfalen-lippe-100.feed",       category: "local",   site: "https://www1.wdr.de", publisher: "WDR" },
    "WDR – Wissen"          => { url: "https://www1.wdr.de/wissen/uebersicht-nachrichten-100.feed",                           category: "science", site: "https://www1.wdr.de", publisher: "WDR" },
    "WDR – Kultur"          => { url: "https://www1.wdr.de/kultur/uebersicht-kultur-100.feed",                                category: "arts",    site: "https://www1.wdr.de", publisher: "WDR" },

    "NDR – Hamburg"                => { url: "https://www.ndr.de/nachrichten/hamburg/index~rss2.xml",                category: "local", site: "https://www.ndr.de", publisher: "NDR" },
    "NDR – Niedersachsen"          => { url: "https://www.ndr.de/nachrichten/niedersachsen/index~rss2.xml",          category: "local", site: "https://www.ndr.de", publisher: "NDR" },
    "NDR – Mecklenburg-Vorpommern" => { url: "https://www.ndr.de/nachrichten/mecklenburg-vorpommern/index~rss2.xml", category: "local", site: "https://www.ndr.de", publisher: "NDR" },
    "NDR – Schleswig-Holstein"     => { url: "https://www.ndr.de/nachrichten/schleswig-holstein/index~rss2.xml",     category: "local", site: "https://www.ndr.de", publisher: "NDR" },
    "NDR – Info"                   => { url: "https://www.ndr.de/nachrichten/info/index~rss2.xml",                   category: "top",    site: "https://www.ndr.de", publisher: "NDR" },
    "NDR – Sport"                  => { url: "https://www.ndr.de/sport/index~rss2.xml",                              category: "sports", site: "https://www.ndr.de", publisher: "NDR" },
    "NDR – Kultur"                 => { url: "https://www.ndr.de/kultur/index~rss2.xml",                             category: "arts",   site: "https://www.ndr.de", publisher: "NDR" }
  }.freeze

  # Publisher metadata per germannews feed URL — the same key seed_feeds!
  # upserts on, so a seeded feed always finds its publisher.
  GERMANNEWS_PUBLISHERS = build_publisher_index(GERMANNEWS_FEEDS).freeze

  # The Australian news catalog from https://rss.feedspot.com/australian_news_rss_feeds/
  # (as of 2026-09-20). Same multi-publisher shape as GERMANNEWS_FEEDS. Of the
  # 45 listed outlets, these are the ones that (a) actually serve a working
  # feed and (b) are a real news outlet rather than a syndication scraper,
  # satire site, or content mill — checked by sampling each candidate feed's
  # actual entries on 2026-09-20. Left out:
  #   - News.com.au, 9News, Herald Sun, NT News: no working feed URL found —
  #     the News Corp/Nine properties either 404 or bounce through a
  #     cookie-check redirect FeedFetcher can't follow.
  #   - Perth Herald / Sydney Sun ("feeds.perthherald.com" / "feeds.sydneysun.com"):
  #     syndication-scraper feeds — entries are reposted wire copy (some
  #     literally credited to abc.net.au) with mangled whitespace-padded
  #     titles, not original publishing.
  #   - Cairns News: real feed, but its actual content is conspiracy-adjacent
  #     ("weapon", "globalists" in ordinary headlines) — excluded on quality,
  #     not availability.
  #   - 16 News, Independent Australia, IBTimes AU, Kalkine Media, The Shovel,
  #     Tasmanian Times, Tech Business News, Australian Newsagency Blog,
  #     Ozzie News: respectively an advocacy blog with editorializing
  #     headlines, a polemic opinion outlet, a tabloid/clickbait aggregator, a
  #     stock-promotion content mill, satire, and three sites returning
  #     403/SSL errors.
  AUSTRALIANEWS_FEEDS = {
    "ABC News"                => { url: "https://www.abc.net.au/news/feed/2942460/rss.xml", category: "top",      site: "https://www.abc.net.au/news" },
    "SBS News"                => { url: "https://www.sbs.com.au/news/feed",                 category: "top",      site: "https://www.sbs.com.au/news" },
    "The Sydney Morning Herald" => { url: "https://www.smh.com.au/rss/feed.xml",             category: "top",      site: "https://www.smh.com.au" },
    "The Age"                 => { url: "https://www.theage.com.au/rss/feed.xml",           category: "top",      site: "https://www.theage.com.au" },
    "The Canberra Times"      => { url: "https://www.canberratimes.com.au/rss.xml",         category: "top",      site: "https://www.canberratimes.com.au" },
    "Brisbane Times"          => { url: "https://www.brisbanetimes.com.au/rss/feed.xml",    category: "top",      site: "https://www.brisbanetimes.com.au" },
    "WAtoday"                 => { url: "https://www.watoday.com.au/rss/feed.xml",          category: "top",      site: "https://www.watoday.com.au" },
    "The West Australian"     => { url: "https://thewest.com.au/rss",                       category: "top",      site: "https://thewest.com.au" },
    "PerthNow"                => { url: "https://www.perthnow.com.au/feed",                 category: "top",      site: "https://www.perthnow.com.au" },
    "Business News"           => { url: "https://www.businessnews.com.au/rssfeed/latest.rss", category: "business", site: "https://www.businessnews.com.au" },
    "Crikey"                  => { url: "https://www.crikey.com.au/feed/",                  category: "opinion",  site: "https://www.crikey.com.au" },
    "The GC Minute"           => { url: "https://www.thegcminute.com.au/feed",              category: "local",    site: "https://www.thegcminute.com.au" },
    "Werribee News"           => { url: "https://www.werribeenews.com.au/feed/",            category: "local",    site: "https://www.werribeenews.com.au" },
    "Alice Springs News"      => { url: "https://www.alicespringsnews.com.au/feed",         category: "local",    site: "https://www.alicespringsnews.com.au" },
    "Goulburn Post"           => { url: "https://www.goulburnpost.com.au/rss.xml",          category: "local",    site: "https://www.goulburnpost.com.au" }
  }.freeze

  AUSTRALIANEWS_PUBLISHERS = build_publisher_index(AUSTRALIANEWS_FEEDS).freeze

  # The Israeli news catalog from https://rss.feedspot.com/israel_news_rss_feeds/
  # (as of 2026-09-20). Kept deliberately small: of the 18 listed outlets,
  # these 4 are the ones that (a) serve a working feed and (b) publish in
  # English — every other translatable source in this app (BBC/NYT/Ad Hoc
  # News/heise/German News) is English or German, and `Prompt` ships one
  # "translate" prompt written and tuned specifically for
  # English-to-Farsi (see db/seeds.rb / Prompt.seed_defaults!), so Hebrew or
  # Russian input would go through a prompt that doesn't expect it. Left out:
  #   - Davar, Hamodia, Maariv, Israel News Agency, DEBKAfile: feed
  #     unreachable (403/404/SSL error) even after trying known alternate
  #     URLs, including Davar's separate English edition.
  #   - Cursorinfo, Vesty: working feeds, but both are Russian-language
  #     editions (for Israel's Russian-speaking readership) — skipped for the
  #     English-prompt reason above, not availability.
  #   - The Jerusalem Post's Feedspot-listed URL 308-redirects (its path is
  #     case-sensitive and Feedspot has it mis-cased); used the working
  #     lowercase URL it redirects to instead, since FeedFetcher doesn't
  #     follow redirects.
  ISRAELNEWS_FEEDS = {
    "Haaretz"               => { url: "https://www.haaretz.com/srv/haaretz-latest-headlines",                       category: "top",      site: "https://www.haaretz.com" },
    "Globes"                => { url: "https://en.globes.co.il/WebService/Rss/RssFeeder.asmx/FeederNode?iID=942",   category: "business", site: "https://en.globes.co.il/en" },
    "Israel National News"  => { url: "https://www.israelnationalnews.com/Rss.aspx",                                category: "top",      site: "https://www.israelnationalnews.com" },
    "The Jerusalem Post"    => { url: "https://www.jpost.com/rss/rssfeedsfrontpage.aspx",                           category: "top",      site: "https://www.jpost.com" }
  }.freeze

  ISRAELNEWS_PUBLISHERS = build_publisher_index(ISRAELNEWS_FEEDS).freeze

  def self.seed_bbc_feeds!
    seed_feeds!(BBC_FEEDS, source: "bbc")
  end

  def self.seed_nyt_feeds!
    seed_feeds!(NYT_FEEDS, source: "nyt")
  end

  def self.seed_adhocnews_feeds!
    seed_feeds!(ADHOCNEWS_FEEDS, source: "adhocnews")
  end

  def self.seed_heise_feeds!
    seed_feeds!(HEISE_FEEDS, source: "heise")
  end

  def self.seed_germannews_feeds!
    seed_feeds!(GERMANNEWS_FEEDS, source: "germannews")
  end

  def self.seed_australianews_feeds!
    seed_feeds!(AUSTRALIANEWS_FEEDS, source: "australianews")
  end

  def self.seed_israelnews_feeds!
    seed_feeds!(ISRAELNEWS_FEEDS, source: "israelnews")
  end

  # Every article-host domain across every multi-publisher catalog, with and
  # without `www.` — used by ArticleImageFetcher to allow-list og:image
  # lookups without hardcoding a per-source list that would drift from the
  # catalogs above.
  def self.all_catalogued_publisher_domains
    MULTI_PUBLISHER_SOURCES.flat_map { |source| const_get("#{source.upcase}_PUBLISHERS").values }
                            .flat_map { |publisher| [ publisher[:domain], "www.#{publisher[:domain]}" ] }
                            .uniq
  end

  # Publisher for a germannews feed an admin added by hand, so it still gets a
  # sensible "read the original on …" link instead of a blank domain.
  def derived_publisher_info
    host = URI.parse(url.to_s).host.to_s.delete_prefix("www.")
    { name:, domain: host, url: host.present? ? "https://#{host}" : "" }
  rescue URI::InvalidURIError
    { name:, domain: "", url: "" }
  end
  private :derived_publisher_info

  def self.seed_feeds!(feed_definitions, source:)
    feed_definitions.each do |name, attrs|
      find_or_create_by!(url: attrs[:url]) do |feed|
        feed.name     = name
        feed.category = attrs[:category]
        feed.source   = source
        feed.enabled  = true
      end
    end
  end
  private_class_method :seed_feeds!
end
