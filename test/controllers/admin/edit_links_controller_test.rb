require "test_helper"

class Admin::EditLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = create_article
    create_translation(rewrite: create_rewrite(article: @article))
  end

  test "reviewer creates a link with the chosen lifetime and it appears on the article page" do
    log_in_as(create_editor_user)
    assert_difference("EditLink.count", 1) do
      post admin_article_edit_links_path(@article), params: { note: "Sara", lifetime_days: "30" }
    end
    edit_link = EditLink.last
    assert_in_delta 30.days.from_now.to_f, edit_link.expires_at.to_f, 60
    assert_equal "Sara", edit_link.note

    get admin_article_path(@article)
    assert_select "#edit_links input[value=?]", guest_edit_url(edit_link.token)
  end

  test "single_use option is stored" do
    log_in_as
    post admin_article_edit_links_path(@article), params: { single_use: "1" }
    assert EditLink.last.single_use?
    post admin_article_edit_links_path(@article), params: { single_use: "0" }
    assert_not EditLink.last.single_use?
  end

  test "unsupported lifetimes fall back to the default" do
    log_in_as
    post admin_article_edit_links_path(@article), params: { lifetime_days: "9999" }
    assert_in_delta EditLink::DEFAULT_LIFETIME_DAYS.days.from_now.to_f, EditLink.last.expires_at.to_f, 60
  end

  test "restricted editors cannot create or revoke links" do
    admin_link = @article.edit_links.create!(created_by: create_admin_user, expires_at: 1.day.from_now)
    log_in_as(create_editor_user(requires_edit_approval: true))

    assert_no_difference("EditLink.count") { post admin_article_edit_links_path(@article) }
    delete admin_edit_link_path(admin_link)
    assert admin_link.reload.usable?
  end

  test "revoking disables the link" do
    admin = log_in_as
    edit_link = @article.edit_links.create!(created_by: admin, expires_at: 1.day.from_now)
    delete admin_edit_link_path(edit_link)
    assert edit_link.reload.revoked?
    get guest_edit_path(edit_link.token)
    assert_response :not_found
  end
end
