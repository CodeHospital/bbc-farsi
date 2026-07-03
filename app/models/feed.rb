class Feed < ApplicationRecord
  has_many :articles, dependent: :destroy

  SOURCES = %w[bbc nyt].freeze

  validates :name, presence: true
  validates :url, presence: true, uniqueness: true
  validates :category, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }

  scope :enabled, -> { where(enabled: true) }

  def title
    "#{name} (#{source.upcase})"
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

  def self.seed_bbc_feeds!
    seed_feeds!(BBC_FEEDS, source: "bbc")
  end

  def self.seed_nyt_feeds!
    seed_feeds!(NYT_FEEDS, source: "nyt")
  end

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
