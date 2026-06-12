require "test_helper"

class Admin::RewritesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
    log_in
  end

  test "lists rewrites with filter controls" do
    create_rewrite
    get admin_rewrites_path
    assert_response :success
    assert_select "a[aria-pressed]" # toggle filter buttons render
  end

  test "filters by status" do
    done = create_rewrite(attrs: { status: "completed" })
    err  = create_rewrite(attrs: { status: "error" })

    get admin_rewrites_path(status: "error")
    assert_select "a[href=?]", admin_rewrite_path(err)
    assert_select "a[href=?]", admin_rewrite_path(done), count: 0
  end

  test "search matches article title" do
    article = create_article(attrs: { title: "Quantum leap" })
    match   = create_rewrite(article: article)
    other   = create_rewrite # default "Test article title"

    get admin_rewrites_path(q: "quantum")
    assert_select "a[href=?]", admin_rewrite_path(match)
    assert_select "a[href=?]", admin_rewrite_path(other), count: 0
  end

  test "search matches rewrite content" do
    match = create_rewrite(attrs: { content: "A story about photosynthesis" })
    other = create_rewrite(attrs: { content: "A story about football" })

    get admin_rewrites_path(q: "photosynthesis")
    assert_select "a[href=?]", admin_rewrite_path(match)
    assert_select "a[href=?]", admin_rewrite_path(other), count: 0
  end

  test "archived toggle reveals archived rewrites" do
    visible  = create_rewrite
    archived = create_rewrite(attrs: { archived: true })

    get admin_rewrites_path
    assert_select "a[href=?]", admin_rewrite_path(visible)
    assert_select "a[href=?]", admin_rewrite_path(archived), count: 0

    get admin_rewrites_path(archived: "1")
    assert_select "a[href=?]", admin_rewrite_path(archived)
  end

  test "sorts by article title ascending and descending" do
    article_z = create_article(attrs: { title: "Zeta article" })
    article_a = create_article(attrs: { title: "Alpha article" })
    create_rewrite(article: article_z)
    create_rewrite(article: article_a)

    get admin_rewrites_path(sort: "article", dir: "asc")
    assert_response :success
    assert_operator response.body.index("Alpha article"), :<, response.body.index("Zeta article")

    get admin_rewrites_path(sort: "article", dir: "desc")
    assert_operator response.body.index("Zeta article"), :<, response.body.index("Alpha article")
  end

  test "defaults to newest first" do
    older_article = create_article(attrs: { title: "Older rewrite article" })
    newer_article = create_article(attrs: { title: "Newer rewrite article" })
    older = create_rewrite(article: older_article)
    newer = create_rewrite(article: newer_article)
    older.update_column(:created_at, 2.days.ago)
    newer.update_column(:created_at, 1.hour.ago)

    get admin_rewrites_path
    assert_operator response.body.index("Newer rewrite article"), :<, response.body.index("Older rewrite article")
  end

  test "column headers are sortable and preserve active filters" do
    create_rewrite(attrs: { status: "completed" })
    get admin_rewrites_path(status: "completed")
    assert_select "thead a[href*='sort=article']"
    assert_select "thead a[href*='sort=model']"
    assert_select "thead a[href*='status=completed']" # filter preserved in sort links
  end

  test "active sort column shows a direction indicator" do
    create_rewrite
    get admin_rewrites_path(sort: "model", dir: "asc")
    assert_select "thead a", text: /Model ▲/
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end
end
