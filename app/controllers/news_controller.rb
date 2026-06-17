# Public-facing news site (no authentication). Shows the latest completed
# Persian translation (or refinement) for each article, BBC-Persian style.
class NewsController < ApplicationController
  layout "news"

  def index
    @stories = latest_translation_per_article
  end

  def show
    @translation = published_translations.find(params[:id])
    @article = @translation.article
  end

  private

  # Completed, non-archived translations that actually have Persian text.
  # Refinements are ordinary Translation rows (prompt_name "refine"), so they
  # naturally appear here once completed.
  def published_translations
    Translation.completed
      .where.not(translated_title: [nil, ""])
      .where(archived: false)
      .includes(article: :feed)
  end

  # One story per article: the most recently created completed translation,
  # so a finished refinement supersedes the translation it improved.
  def latest_translation_per_article
    published_translations
      .order(created_at: :desc)
      .group_by(&:article_id)
      .map { |_article_id, versions| versions.first }
      .reject { |translation| translation.article.archived? }
      .sort_by { |translation| translation.article.published_at || translation.created_at }
      .reverse
  end
end
