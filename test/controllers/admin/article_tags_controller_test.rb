require "test_helper"

class Admin::ArticleTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = create_article(feed: create_feed(name: "World", name_fa: "جهان"))
  end

  test "the article page shows the feed as the default tag and the article's tags" do
    log_in_as
    @article.tags << Tag.create!(name_fa: "ایران", name_en: "Iran")

    get admin_article_path(@article)

    assert_response :success
    assert_select "#tags .badge", /جهان \/ World/
    assert_select "#tags .badge", /ایران/
    assert_select "#tags form[action=?]", admin_article_tags_path(@article)
  end

  test "adding a new tag creates it with both names" do
    log_in_as

    post admin_article_tags_path(@article), params: { name_fa: "نفت", name_en: "Oil" }

    assert_redirected_to admin_article_path(@article, anchor: "tags")
    assert_equal [ [ "نفت", "Oil" ] ], @article.tags.pluck(:name_fa, :name_en)
  end

  test "adding by one name reuses the existing tag" do
    log_in_as
    existing_tag = Tag.create!(name_fa: "ایران", name_en: "Iran")

    assert_no_difference("Tag.count") { post admin_article_tags_path(@article), params: { name_en: "iran" } }

    assert_equal [ existing_tag ], @article.tags.to_a
  end

  test "adding with no name is rejected" do
    log_in_as

    post admin_article_tags_path(@article), params: { name_fa: " ", name_en: "" }

    assert_equal "Enter a Persian or an English tag name.", flash[:alert]
    assert_empty @article.tags
  end

  test "removing a tag unlinks it from the article but keeps the tag" do
    log_in_as
    tag = Tag.create!(name_fa: "ایران", name_en: "Iran")
    @article.tags << tag

    delete admin_article_tag_path(@article, tag)

    assert_empty @article.reload.tags
    assert Tag.exists?(tag.id)
  end

  test "an editor whose edits need approval cannot change an article's tags" do
    log_in_as(create_editor_user(requires_edit_approval: true))

    post admin_article_tags_path(@article), params: { name_fa: "نفت", name_en: "Oil" }

    assert_empty @article.tags
    get admin_article_path(@article)
    assert_select "#tags form[action=?]", admin_article_tags_path(@article), 0
  end
end
