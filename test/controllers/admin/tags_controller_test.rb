require "test_helper"

class Admin::TagsControllerTest < ActionDispatch::IntegrationTest
  test "admin lists, filters, adds, renames and deletes tags" do
    log_in_as
    complete_tag = Tag.create!(name_fa: "ایران", name_en: "Iran")
    persian_only = Tag.create!(name_fa: "اقتصاد")
    create_article.tags << complete_tag

    get admin_tags_path
    assert_response :success
    assert_select "#tag_#{complete_tag.id}"
    assert_select "#tag_#{persian_only.id}.table-warning"

    get admin_tags_path(missing: "1")
    assert_select "#tag_#{complete_tag.id}", 0
    assert_select "#tag_#{persian_only.id}"

    post admin_tags_path, params: { tag: { name_fa: "نفت", name_en: "Oil" } }
    assert Tag.exists?(name_fa: "نفت", name_en: "Oil")

    patch admin_tag_path(persian_only), params: { tag: { name_fa: "اقتصاد", name_en: "Economy" } }
    assert_equal "Economy", persian_only.reload.name_en

    patch admin_tag_path(persian_only), params: { tag: { name_fa: "", name_en: "" } }
    assert_match(/Persian or an English name/, flash[:alert])

    assert_difference("ArticleTag.count", -1) { delete admin_tag_path(complete_tag) }
    refute Tag.exists?(complete_tag.id)
  end

  test "an unrestricted editor can edit tags" do
    log_in_as(create_editor_user)
    tag = Tag.create!(name_fa: "ایران")

    patch admin_tag_path(tag), params: { tag: { name_fa: "ایران", name_en: "Iran" } }

    assert_equal "Iran", tag.reload.name_en
  end

  test "an editor whose edits need approval can view but not change tags" do
    log_in_as(create_editor_user(requires_edit_approval: true))
    tag = Tag.create!(name_fa: "ایران")

    get admin_tags_path
    assert_response :success
    assert_select "form#edit_tag_#{tag.id}", 0

    patch admin_tag_path(tag), params: { tag: { name_en: "Iran" } }
    assert_nil tag.reload.name_en
    assert_equal "You don't have permission to edit tags.", flash[:alert]
  end
end
