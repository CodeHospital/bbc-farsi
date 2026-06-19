# A lightweight, Translation-shaped wrapper around a raw Article that has no
# completed Persian translation yet. It lets the public news views treat an
# untranslated article exactly like a translated "story" object, so the English
# edition can surface fresh BBC news the moment it is ingested — before the
# rewrite/translate worker pipeline has produced a Persian version.
#
# It duck-types the slice of the Translation interface the news views/helpers
# use: `article`, `article_id`, `translated_title`, `translated_body`,
# `created_at`, `updated_at`, and `seo_param`. Because there is no Persian text,
# the "translated" accessors fall back to the original English article fields,
# which keeps NewsHelper#story_title/#story_body working in either edition.
class ArticleStory
  attr_reader :article

  def initialize(article)
    @article = article
  end

  def article_id = article.id
  def created_at = article.created_at
  def updated_at = article.updated_at

  # No Persian version exists yet, so fall back to the original article text.
  def translated_title = article.title
  def translated_body  = article.description

  # Friendly public URL param. Prefixed with "a-" so news#show distinguishes
  # article stories from translation stories (which never start with "a-").
  # Uses the stored article.slug column when available; falls back to the old
  # "a<id>-<title-slug>" format so URLs keep working before migration runs.
  def seo_param
    if Article.column_names.include?("slug") && article.slug.present?
      "a-#{article.slug}"
    else
      computed_parts = article.title.to_s.strip
        .gsub(/[[:space:]]+/, "-")
        .gsub(/[^[[:word:]]\-]/, "")
        .gsub(/-+/, "-")
        .gsub(/\A-+|-+\z/, "")
        .presence
      [ "a#{article.id}", computed_parts ].compact_blank.join("-")
    end
  end
end
