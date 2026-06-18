# Chooses which stories are "featured" on the public homepage.
#
# Two layers, by design (see plan):
#   * Heuristic (always available): prioritises high-impact categories, newest
#     first — used immediately and as a fallback.
#   * AI (via the worker queue): `bbc:feature` enqueues a `feature` Task whose
#     LLM request asks the model to pick the most newsworthy article IDs. When
#     the worker completes it, the chosen IDs are cached here (no schema change)
#     and take precedence over the heuristic until they expire.
class FeaturedSelector
  CACHE_KEY     = "featured_article_ids".freeze
  CACHE_TTL     = 3.hours
  DEFAULT_LIMIT = 3
  # Newest candidates considered by the AI selector (keeps the prompt bounded).
  CANDIDATE_POOL = 25

  # Lower rank = more likely to be featured by the heuristic fallback.
  CATEGORY_RANK = { "top" => 0, "world" => 1, "business" => 2, "uk" => 3,
                    "technology" => 4, "science" => 5, "health" => 6 }.freeze

  SYSTEM_PROMPT = <<~PROMPT.strip
    You are a senior Persian news editor choosing which stories to feature at the
    top of a news homepage. Pick the stories with the broadest public interest and
    the greatest impact. Respond with ONLY the chosen ID numbers separated by
    commas (for example: 12, 7, 30). Output no other text.
  PROMPT

  # ── Selection used by the public homepage ────────────────────────────────

  # Returns [featured_stories, remaining_stories]. Uses the AI-cached IDs when
  # present; otherwise falls back to the heuristic. `stories` are Translations.
  def self.select(stories, limit: DEFAULT_LIMIT)
    featured = from_cache(stories, limit)
    featured = heuristic(stories, limit) if featured.empty?
    [ featured, stories - featured ]
  end

  def self.from_cache(stories, limit)
    ids = featured_ids
    return [] if ids.empty?

    by_article = stories.index_by(&:article_id)
    ids.filter_map { |article_id| by_article[article_id] }.first(limit)
  end

  def self.heuristic(stories, limit)
    stories.sort_by { |translation|
      [ CATEGORY_RANK.fetch(translation.article.feed&.category, 99),
        -(translation.article.published_at || translation.created_at).to_i ]
    }.first(limit)
  end

  # ── AI selection cache ────────────────────────────────────────────────────

  def self.featured_ids
    Array(Rails.cache.read(CACHE_KEY))
  end

  def self.store(article_ids)
    Rails.cache.write(CACHE_KEY, Array(article_ids), expires_in: CACHE_TTL)
  end

  # ── LLM request / response (run through the worker queue) ──────────────────

  def self.requests(candidates, limit: DEFAULT_LIMIT)
    listing = candidates.map { |t| "ID #{t.article_id}: #{t.translated_title}" }.join("\n")
    [
      {
        key: "featured",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: "Choose the #{limit} most newsworthy stories:\n\n#{listing}" }
        ]
      }
    ]
  end

  # Extracts the chosen article IDs from the worker's response text.
  def self.process(responses)
    responses["featured"].to_s.scan(/\d+/).map(&:to_i).uniq
  end

  # ── Candidate pool for the AI selector ─────────────────────────────────────

  # The newest completed, non-archived translations (one per article) — the same
  # universe the homepage shows, capped to keep the prompt small.
  def self.candidates
    Translation.completed
      .where.not(translated_title: [ nil, "" ])
      .where(archived: false)
      .includes(:article)
      .order(created_at: :desc)
      .group_by(&:article_id)
      .map { |_id, versions| versions.first }
      .reject { |t| t.article.archived? }
      .first(CANDIDATE_POOL)
  end
end
