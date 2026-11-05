require "test_helper"

class Admin::ArticleTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = create_article(feed: create_feed(name: "World", name_fa: "جهان"))
    @feed_tag = @article.feed.tag
  end

  test "the article page lists its tags, the feed's tag first, all removable" do
    log_in_as
    topic_tag = Tag.create!(name_fa: "ایران", name_en: "Iran")
    @article.tags << topic_tag

    get admin_article_path(@article)

    assert_response :success
    badges = css_select("#tags .badge").map { |badge| badge.text.squish }
    assert_match(/جهان/, badges.first)
    assert_match(/ایران/, badges.second)
    assert_select "#tags form[action=?]", admin_article_tag_path(@article, @feed_tag)
    assert_select "#tags form[action=?]", admin_article_tag_path(@article, topic_tag)
    assert_select "#tags form[action=?]", admin_article_tags_path(@article)
  end

  test "adding a new tag creates it with both names" do
    log_in_as

    post admin_article_tags_path(@article), params: { name_fa: "نفت", name_en: "Oil" }

    assert_redirected_to admin_article_path(@article, anchor: "tags")
    assert_equal [ "نفت", "Oil" ], @article.ordered_tags.last.then { |tag| [ tag.name_fa, tag.name_en ] }
  end

  test "adding by one name reuses the existing tag" do
    log_in_as
    existing_tag = Tag.create!(name_fa: "ایران", name_en: "Iran")

    assert_no_difference("Tag.count") { post admin_article_tags_path(@article), params: { name_en: "iran" } }

    assert_equal [ @feed_tag, existing_tag ], @article.ordered_tags
  end

  test "adding with no name is rejected" do
    log_in_as

    post admin_article_tags_path(@article), params: { name_fa: " ", name_en: "" }

    assert_equal "Enter a Persian or an English tag name.", flash[:alert]
    assert_equal [ @feed_tag ], @article.tags.to_a
  end

  test "removing a tag (the feed's tag too) unlinks it from the article but keeps the tag" do
    log_in_as
    tag = Tag.create!(name_fa: "ایران", name_en: "Iran")
    @article.tags << tag

    delete admin_article_tag_path(@article, tag)
    delete admin_article_tag_path(@article, @feed_tag)

    assert_empty @article.reload.tags
    assert Tag.exists?(tag.id)
    assert Tag.exists?(@feed_tag.id)
  end

  test "an editor whose edits need approval cannot change an article's tags" do
    log_in_as(create_editor_user(requires_edit_approval: true))

    post admin_article_tags_path(@article), params: { name_fa: "نفت", name_en: "Oil" }

    assert_equal [ @feed_tag ], @article.tags.to_a
    get admin_article_path(@article)
    assert_select "#tags form[action=?]", admin_article_tags_path(@article), 0
  end
end
