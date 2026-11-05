# Bilingual article tags: list, search, add, rename (Persian and English
# names) and delete. Deleting a tag removes it from every article.
class Admin::TagsController < Admin::BaseController
  include Pagy::Method

  before_action :require_tag_editor!, except: :index
  before_action :set_tag, only: %i[update destroy]

  def index
    tags = Tag.left_joins(:article_tags)
              .select("tags.*, COUNT(article_tags.id) AS articles_count")
              .group("tags.id")
    if params[:q].present?
      search_pattern = "%#{params[:q].strip.downcase}%"
      tags = tags.where("LOWER(tags.name_fa) LIKE ? OR LOWER(tags.name_en) LIKE ?", search_pattern, search_pattern)
    end
    tags = tags.missing_translation if params[:missing] == "1"
    @missing_translation_count = Tag.missing_translation.count
    @pagy, @tags = pagy(tags.order(Arel.sql("COUNT(article_tags.id) DESC, COALESCE(tags.name_fa, tags.name_en)")))
    @new_tag = Tag.new
  end

  def create
    @new_tag = Tag.new(tag_params)
    if @new_tag.save
      redirect_to admin_tags_path, notice: "Tag “#{@new_tag.display_name}” added."
    else
      redirect_to admin_tags_path, alert: @new_tag.errors.full_messages.to_sentence
    end
  end

  def update
    if @tag.update(tag_params)
      redirect_back fallback_location: admin_tags_path, notice: "Tag “#{@tag.display_name}” updated."
    else
      redirect_back fallback_location: admin_tags_path, alert: @tag.errors.full_messages.to_sentence
    end
  end

  def destroy
    @tag.destroy!
    redirect_back fallback_location: admin_tags_path, notice: "Tag “#{@tag.display_name}” deleted from every article."
  end

  private

  def set_tag = @tag = Tag.find(params[:id])
  def tag_params = params.require(:tag).permit(:name_fa, :name_en)
end
