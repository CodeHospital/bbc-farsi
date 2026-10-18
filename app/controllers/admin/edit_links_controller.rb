# Create / revoke the magic links shown on an article's admin page. Limited to
# people who can review edits, since the resulting proposals land in the
# review queue.
class Admin::EditLinksController < Admin::BaseController
  before_action :require_edit_reviewer!

  def create
    article   = Article.find(params[:article_id])
    lifetime  = params[:lifetime_days].to_i
    lifetime  = EditLink::DEFAULT_LIFETIME_DAYS unless EditLink::LIFETIME_DAYS_OPTIONS.include?(lifetime)
    edit_link = article.edit_links.build(created_by: current_user, note: params[:note].to_s.strip.presence,
                                         expires_at: lifetime.days.from_now, single_use: params[:single_use] == "1")

    if edit_link.save
      redirect_to admin_article_path(article, anchor: "edit_links"), notice: "#{edit_link.usage_label.capitalize} edit link created (valid #{lifetime} day#{'s' unless lifetime == 1})."
    else
      redirect_to admin_article_path(article, anchor: "edit_links"), alert: edit_link.errors.full_messages.to_sentence
    end
  end

  def destroy
    edit_link = EditLink.find(params[:id])
    edit_link.revoke!
    redirect_to admin_article_path(edit_link.article, anchor: "edit_links"), notice: "Edit link revoked."
  end
end
