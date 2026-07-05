# Generates AI topic tags (Persian keywords) for a translated article.
#
# Runs through the worker queue (a `tag` Task): the LLM is given the Persian
# title and body and asked for a few short topic tags. The result is cached per
# article (no schema change) and shown on the public news pages.
class TagGenerator
  CACHE_TTL  = 30.days
  MAX_TAGS   = 6

  # Prompt text is DB-backed (see Prompt) so admins/editors can edit it; the
  # request always uses the current version, and embeds its prompt_version_id
  # so Task can record which version produced the result.
  def self.requests(translation)
    version = Prompt.current_version("tag")
    [
      {
        key: "tags",
        prompt_version_id: version.id,
        messages: [
          { role: "system", content: version.content },
          { role: "user",   content: "Title: #{translation.translated_title}\n\nBody: #{translation.translated_body}" }
        ]
      }
    ]
  end

  # Parses the worker's comma/newline-separated tag list into a clean array.
  def self.process(responses)
    responses["tags"].to_s
      .gsub(%r{<think>.*?</think>}m, "")
      .split(/[,\n،]/)
      .map { |tag| tag.strip.delete_prefix("#") }
      .reject(&:empty?)
      .uniq
      .first(MAX_TAGS)
  end

  # ── Per-article cache ──────────────────────────────────────────────────────

  def self.cache_key(article_id) = "article_tags/#{article_id}"

  def self.store(article_id, tags)
    Rails.cache.write(cache_key(article_id), Array(tags), expires_in: CACHE_TTL)
  end

  def self.tags_for(article)
    Array(Rails.cache.read(cache_key(article.id)))
  end

  def self.tagged?(article)
    Rails.cache.exist?(cache_key(article.id))
  end

  # Newest completed, non-archived translations (one per article) that don't yet
  # have cached tags — the work `bbc:tag` enqueues.
  def self.untagged_candidates
    Translation.completed
      .where.not(translated_title: [ nil, "" ])
      .where(archived: false)
      .includes(:article)
      .order(created_at: :desc)
      .group_by(&:article_id)
      .map { |_id, versions| versions.first }
      .reject { |t| t.article.archived? || tagged?(t.article) }
  end
end
