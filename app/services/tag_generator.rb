# Generates AI topic tags for a translated article.
#
# Runs through the worker queue (a `tag` Task): the LLM is given the Persian
# title and body and asked for a few short topic tags, each as a
# "Persian | English" pair. The tags are stored as bilingual Tag rows linked
# to the article (ArticleTag), where admins/editors can edit them. Every
# story's default tag — its source feed — is not generated here; it comes from
# the feed itself (see NewsHelper#feed_tag_label).
class TagGenerator
  MAX_TAGS = 6
  # Cache key prefix of the pre-database tags (see `import_cached_tags!`).
  LEGACY_CACHE_PREFIX = "article_tags".freeze

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

  # Parses the worker's comma/newline-separated tag list into
  # `{ name_fa:, name_en: }` pairs. Each item is either "فارسی | English" or a
  # single name (older prompt versions answer in Persian only), which is filed
  # under the language its script belongs to.
  def self.process(responses)
    responses["tags"].to_s
      .gsub(%r{<think>.*?</think>}m, "")
      .split(/[,\n،]/)
      .filter_map { |item| parse_item(item) }
      .uniq { |pair| [ pair[:name_fa], pair[:name_en]&.downcase ] }
      .first(MAX_TAGS)
  end

  def self.parse_item(item)
    names = item.split("|").map { |name| clean_name(name) }.compact
    return if names.empty?

    persian_name = names.find { |name| name.match?(Tag::PERSIAN_SCRIPT) }
    english_name = names.find { |name| !name.match?(Tag::PERSIAN_SCRIPT) }
    { name_fa: persian_name, name_en: english_name }
  end

  def self.clean_name(name) = name.to_s.strip.delete_prefix("#").squish.presence

  # `tag_pairs` are `{ name_fa:, name_en: }` hashes (or raw "fa | en" strings).
  # Links the generated tags to the article (keeping any tags an editor
  # already set — AI tagging only ever adds) and marks it as tagged.
  def self.store(article_id, tag_pairs)
    article = Article.find(article_id)
    Article.transaction do
      Array(tag_pairs).each do |pair|
        pair = pair.is_a?(String) ? parse_item(pair) : pair.to_h.symbolize_keys.slice(:name_fa, :name_en)
        next unless pair

        tag = Tag.resolve(**pair)
        article.article_tags.find_or_create_by!(tag:) if tag
      end
      article.update!(tags_generated_at: Time.current)
    end
  end

  # The article's tags in a portal edition's language ("fa"/"en"), skipping
  # tags not yet translated into it.
  def self.tags_for(article, language: "fa")
    article.tags.sort_by(&:id).filter_map { |tag| tag.name_for(language) }
  end

  def self.tagged?(article) = article.tags_generated_at.present? || article.article_tags.exists?

  # Newest completed, non-archived translations (one per article) whose
  # article was never tagged — the work `bbc:tag` enqueues.
  def self.untagged_candidates
    Translation.completed
      .where.not(translated_title: [ nil, "" ])
      .where(archived: false)
      .joins(:article)
      .where(articles: { archived: false, tags_generated_at: nil })
      .where.not(article_id: ArticleTag.select(:article_id))
      .includes(:article)
      .order(created_at: :desc)
      .group_by(&:article_id)
      .map { |_id, versions| versions.first }
  end

  # One-off move of tags generated before tags were stored in the database
  # (Persian-only lists cached under "article_tags/<article id>"). Returns the
  # number of articles imported. Run via `bin/rails bbc:import_cached_tags`.
  def self.import_cached_tags!
    imported_count = 0
    Article.where(tags_generated_at: nil).find_each do |article|
      cached_names = Rails.cache.read("#{LEGACY_CACHE_PREFIX}/#{article.id}")
      next if cached_names.nil?

      store(article.id, Array(cached_names).filter_map { |name| parse_item(name.to_s) })
      imported_count += 1
    end
    imported_count
  end
end
