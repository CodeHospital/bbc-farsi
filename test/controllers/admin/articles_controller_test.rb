require "test_helper"

class Admin::ArticlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
    log_in
  end

  test "lists articles with filter controls" do
    create_article
    get admin_articles_path
    assert_response :success
    assert_select "a[aria-pressed]" # toggle filter buttons render
  end

  test "filters by status" do
    pend = create_article(attrs: { status: "pending" })
    done = create_article(attrs: { status: "posted" })

    get admin_articles_path(status: "posted")
    assert_response :success
    assert_select "a[href=?]", admin_article_path(done)
    assert_select "a[href=?]", admin_article_path(pend), count: 0
  end

  test "filters by feed" do
    feed_a = create_feed(name: "Tech")
    feed_b = create_feed(name: "World")
    a = create_article(feed: feed_a)
    b = create_article(feed: feed_b)

    get admin_articles_path(feed_id: feed_b.id)
    assert_select "a[href=?]", admin_article_path(b)
    assert_select "a[href=?]", admin_article_path(a), count: 0
  end

  test "search matches title or description" do
    match = create_article(attrs: { title: "Quantum leap" })
    other = create_article(attrs: { title: "Sports day" })

    get admin_articles_path(q: "quantum")
    assert_select "a[href=?]", admin_article_path(match)
    assert_select "a[href=?]", admin_article_path(other), count: 0
  end

  test "archived toggle reveals archived articles" do
    visible  = create_article
    archived = create_article(attrs: { archived: true })

    get admin_articles_path
    assert_select "a[href=?]", admin_article_path(visible)
    assert_select "a[href=?]", admin_article_path(archived), count: 0

    get admin_articles_path(archived: "1")
    assert_select "a[href=?]", admin_article_path(archived)
    assert_select "a[href=?]", admin_article_path(visible), count: 0
  end

  test "active status filter toggles off" do
    create_article(attrs: { status: "posted" })
    get admin_articles_path(status: "posted")
    assert_select "a[aria-pressed=true][href=?]", admin_articles_path
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end
end
