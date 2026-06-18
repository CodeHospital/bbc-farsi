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

  # Friendly public URL param. Prefixed with "a" so the news#show action can
  # tell an article-only story ("a123-slug") apart from a translation story
  # ("123-slug", which always starts with a digit) and resolve it correctly.
  def seo_param
    [ "a#{article.id}", slug ].compact_blank.join("-")
  end

  # A URL slug from the (English) article title: word characters kept,
  # everything else collapsed to single hyphens. Mirrors Translation#slug.
  def slug
    article.title.to_s.strip
      .gsub(/[[:space:]]+/, "-")
      .gsub(/[^[[:word:]]\-]/, "")
      .gsub(/-+/, "-")
      .gsub(/\A-+|-+\z/, "")
      .presence
  end
end
