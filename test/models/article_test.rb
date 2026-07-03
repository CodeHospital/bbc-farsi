require "test_helper"

class ArticleTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    assert create_article.valid?
  end

  test "invalid without title" do
    article = Article.new(feed: create_feed, url: "https://bbc.co.uk/x", status: "pending")
    assert_not article.valid?
    assert_includes article.errors[:title], "can't be blank"
  end

  test "invalid without url" do
    article = Article.new(feed: create_feed, title: "Title", status: "pending")
    assert_not article.valid?
  end

  test "url must be unique" do
    a1 = create_article
    a2 = Article.new(feed: a1.feed, title: "Another", url: a1.url, status: "pending")
    assert_not a2.valid?
  end

  test "status must be in STATUSES list" do
    article = create_article
    article.status = "unknown_status"
    assert_not article.valid?
  end

  test "ignorable? is true for title with ignored prefix" do
    assert Article.ignorable?("Watch: something", "https://bbc.co.uk/news/a")
    assert Article.ignorable?("Podcast: episode 5", "https://bbc.co.uk/news/b")
  end

  test "ignorable? is true for url with ignored keyword" do
    assert Article.ignorable?("Fine title", "https://bbc.co.uk/iplayer/episode/1")
    assert Article.ignorable?("Fine title", "https://bbc.co.uk/sounds/play/1")
  end

  test "ignorable? is false for normal articles" do
    assert_not Article.ignorable?("UK election update", "https://bbc.co.uk/news/uk-123")
  end

  test "ignore_reason explains a matched title prefix" do
    reason = Article.ignore_reason("Watch: something", "https://bbc.co.uk/news/a")
    assert_match(/title starts with ignored prefix/, reason)
    assert_match(/Watch:/, reason)
  end

  test "ignore_reason explains a matched url keyword" do
    reason = Article.ignore_reason("Fine title", "https://bbc.co.uk/iplayer/episode/1")
    assert_match(/URL contains ignored keyword/, reason)
    assert_match(/iplayer/, reason)
  end

  test "ignore_reason is nil for normal articles" do
    assert_nil Article.ignore_reason("UK election update", "https://bbc.co.uk/news/uk-123")
  end

  test "latest_rewrite returns most recent rewrite" do
    article = create_article
    old_rewrite = Rewrite.create!(article:, llm_model: "qwen3:14b", status: "completed", content: "old", created_at: 1.hour.ago)
    new_rewrite = Rewrite.create!(article:, llm_model: "qwen3:14b", status: "completed", content: "new")
    assert_equal new_rewrite, article.latest_rewrite
  end
end
