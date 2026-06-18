class SearchQuery < ApplicationRecord
  validates :keyword, presence: true

  # Record a search. Silently swallows errors so a missing migration or DB
  # hiccup never surfaces to the reader.
  def self.track!(keyword, edition: "fa", results_count: 0)
    create!(keyword: keyword.strip.downcase, edition: edition, results_count: results_count)
  rescue => error
    Rails.logger.warn("[SearchQuery] tracking failed: #{error.message}")
  end

  def self.table_exists?
    connection.table_exists?(:search_queries)
  rescue
    false
  end
end
