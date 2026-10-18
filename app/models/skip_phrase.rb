# A phrase that makes feed ingestion skip an entry. Admin-editable at
# /admin/skip_phrases. `match_field` picks what is searched (the entry title or
# its URL); matching is a case-insensitive substring.
class SkipPhrase < ApplicationRecord
  has_paper_trail

  MATCH_FIELDS = %w[title url].freeze
  CACHE_KEY    = "skip_phrases/enabled".freeze

  # What shipped hard-coded in Article before this became editable.
  DEFAULT_PHRASES = {
    "title" => %w[Watch: Assignment: Speak: Podcast: Newsletter: Trending:],
    "url"   => %w[iplayer programmes sounds]
  }.freeze

  before_validation { self.phrase = phrase.strip if phrase }

  validates :phrase, presence: true, uniqueness: { scope: :match_field, case_sensitive: false }
  validates :match_field, inclusion: { in: MATCH_FIELDS }

  after_commit { Rails.cache.delete(CACHE_KEY) }

  scope :enabled, -> { where(enabled: true) }

  # Enabled phrases as { "title" => [...], "url" => [...] }, cached so a feed
  # with hundreds of entries doesn't query once per entry.
  def self.enabled_by_field
    Rails.cache.fetch(CACHE_KEY, expires_in: 1.hour) do
      MATCH_FIELDS.index_with { |field| enabled.where(match_field: field).order(:id).pluck(:phrase) }
    end
  end

  # Idempotent; used by db/seeds.rb and tests.
  def self.seed_defaults!
    DEFAULT_PHRASES.each do |match_field, phrases|
      phrases.each { |phrase| find_or_create_by!(match_field:, phrase:) }
    end
  end
end
