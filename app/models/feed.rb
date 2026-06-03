class Feed < ApplicationRecord
  has_many :articles, dependent: :destroy

  validates :name, presence: true
  validates :url, presence: true, uniqueness: true
  validates :category, presence: true

  scope :enabled, -> { where(enabled: true) }

  BBC_FEEDS = {
    "Top News"   => { url: "https://feeds.bbci.co.uk/news/rss.xml",                          category: "top" },
    "World"      => { url: "https://feeds.bbci.co.uk/news/world/rss.xml",                    category: "world" },
    "UK"         => { url: "https://feeds.bbci.co.uk/news/uk/rss.xml",                       category: "uk" },
    "Business"   => { url: "https://feeds.bbci.co.uk/news/business/rss.xml",                 category: "business" },
    "Technology" => { url: "https://feeds.bbci.co.uk/news/technology/rss.xml",               category: "technology" },
    "Science"    => { url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",  category: "science" },
    "Health"     => { url: "https://feeds.bbci.co.uk/news/health/rss.xml",                   category: "health" }
  }.freeze

  def self.seed_bbc_feeds!
    BBC_FEEDS.each do |name, attrs|
      find_or_create_by!(url: attrs[:url]) do |feed|
        feed.name     = name
        feed.category = attrs[:category]
        feed.enabled  = true
      end
    end
  end
end
