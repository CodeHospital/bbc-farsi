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

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end
end
