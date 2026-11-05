# Adds/removes tags on one article (from the admin article page). Adding takes
# a Persian and/or English name: an existing tag with either name is reused
# (and its missing name filled in), otherwise a new tag is created.
class Admin::ArticleTagsController < Admin::BaseController
  before_action :require_tag_editor!
  before_action :set_article

  def create
    tag = Tag.resolve(name_fa: params[:name_fa], name_en: params[:name_en])
    if tag.nil?
      redirect_to admin_article_path(@article, anchor: "tags"), alert: "Enter a Persian or an English tag name."
    else
      @article.article_tags.find_or_create_by!(tag:)
      redirect_to admin_article_path(@article, anchor: "tags"), notice: "Tag “#{tag.display_name}” added."
    end
  rescue ActiveRecord::RecordInvalid => error
    Sentry.capture_exception(error)
    redirect_to admin_article_path(@article, anchor: "tags"), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    article_tag = @article.article_tags.find_by!(tag_id: params[:id])
    article_tag.destroy!
    redirect_to admin_article_path(@article, anchor: "tags"), notice: "Tag “#{article_tag.tag.display_name}” removed."
  end

  private

  def set_article = @article = Article.find(params[:article_id])
end
