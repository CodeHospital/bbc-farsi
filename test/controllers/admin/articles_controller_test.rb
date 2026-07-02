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

  test "english search finds articles by source title and description" do
    match_by_title = create_article(attrs: { title: "Climate summit begins" })
    match_by_desc  = create_article(attrs: { title: "Other article", description: "Climate change is discussed" })
    no_match       = create_article(attrs: { title: "Football results" })

    get admin_articles_path(q: "climate")
    assert_select "a[href=?]", admin_article_path(match_by_title)
    assert_select "a[href=?]", admin_article_path(match_by_desc)
    assert_select "a[href=?]", admin_article_path(no_match), count: 0
  end

  test "farsi search finds articles by translated title" do
    matching_article    = create_article(attrs: { title: "UK Economy" })
    non_matching_article = create_article(attrs: { title: "Sports news" })

    rewrite = create_rewrite(article: matching_article)
    create_translation(rewrite:, attrs: { translated_title: "اقتصاد بریتانیا در بحران" })

    get admin_articles_path(q: "اقتصاد")
    assert_select "a[href=?]", admin_article_path(matching_article)
    assert_select "a[href=?]", admin_article_path(non_matching_article), count: 0
  end

  test "farsi search does not match english source fields" do
    article = create_article(attrs: { title: "اقتصاد", description: "اخبار" })

    get admin_articles_path(q: "اقتصاد")
    assert_select "a[href=?]", admin_article_path(article), count: 0
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

  test "hide_posted filter excludes posted articles" do
    visible = create_article(attrs: { title: "Pending article", status: "pending" })
    posted  = create_article(attrs: { title: "Posted article",  status: "posted" })

    get admin_articles_path(hide_posted: "1")
    assert_select "a[href=?]", admin_article_path(visible)
    assert_select "a[href=?]", admin_article_path(posted), count: 0
  end

  test "posted article titles show strikethrough class" do
    create_article(attrs: { title: "Done article", status: "posted" })
    get admin_articles_path
    assert_select "a.posted-title", text: /Done article/
  end

  test "sorts by title ascending and descending" do
    create_article(attrs: { title: "Zeta story" })
    create_article(attrs: { title: "Alpha story" })

    get admin_articles_path(sort: "title", dir: "asc")
    assert_response :success
    assert_operator response.body.index("Alpha story"), :<, response.body.index("Zeta story")

    get admin_articles_path(sort: "title", dir: "desc")
    assert_operator response.body.index("Zeta story"), :<, response.body.index("Alpha story")
  end

  test "defaults to newest first" do
    older = create_article(attrs: { title: "Older article" })
    newer = create_article(attrs: { title: "Newer article" })
    older.update_column(:created_at, 2.days.ago)
    newer.update_column(:created_at, 1.hour.ago)

    get admin_articles_path
    assert_operator response.body.index("Newer article"), :<, response.body.index("Older article")
  end

  test "column headers are sortable and preserve active filters" do
    create_article(attrs: { status: "pending" })
    get admin_articles_path(status: "pending")
    assert_select "thead a[href*='sort=title']"
    assert_select "thead a[href*='sort=published']"
    assert_select "thead a[href*='status=pending']" # filter preserved in sort links
  end

  test "active sort column shows a direction indicator" do
    create_article(attrs: { title: "Test" })
    get admin_articles_path(sort: "title", dir: "asc")
    assert_select "thead a", text: /Title ▲/
  end

  test "show renders a prioritize button next to a pending task" do
    article = create_article
    rewrite = create_rewrite(article:, attrs: { status: "pending" })
    task = Task.create!(kind: "rewrite", status: "pending", target: rewrite, model: "qwen3:14b")

    get admin_article_path(article)

    assert_response :success
    assert_select "form[action=?]", prioritize_admin_task_path(task)
  end

  test "show does not render priority controls for a completed task" do
    article = create_article
    rewrite = create_rewrite(article:, attrs: { status: "completed" })
    task = Task.create!(kind: "rewrite", status: "completed", target: rewrite, model: "qwen3:14b")

    get admin_article_path(article)

    assert_response :success
    assert_select "form[action=?]", prioritize_admin_task_path(task), count: 0
  end

  test "show lists all tasks for the article with kind, status, and external job id" do
    article  = create_article
    rewrite  = create_rewrite(article:, attrs: { status: "completed" })
    task     = Task.create!(kind: "rewrite", status: "claimed", target: rewrite,
                             model: "qwen3:14b", external_job_id: "job-123")

    get admin_article_path(article)

    assert_response :success
    assert_select "a[href=?]", admin_task_path(task), text: "##{task.id}"
    assert_select "span.badge", text: "rewrite"
    assert_select "td", text: "job-123"
  end

  test "show renders a placeholder for tasks without an external job id" do
    article = create_article
    rewrite = create_rewrite(article:, attrs: { status: "pending" })
    Task.create!(kind: "rewrite", status: "pending", target: rewrite, model: "qwen3:14b")

    get admin_article_path(article)

    assert_response :success
    assert_select "td", text: "—", minimum: 1
  end

  test "show lists page views for the article with country and city" do
    article = create_article
    ArticleView.create!(article:, edition: "fa", country_name: "Iran", city_name: "Tehran", country_code: "IR")

    get admin_article_path(article)

    assert_response :success
    assert_select "td", text: "Tehran"
  end

  test "show says no views recorded yet when the article has none" do
    article = create_article

    get admin_article_path(article)

    assert_response :success
    assert_select "p.text-muted", text: "No views recorded yet."
  end

  test "show paginates page views" do
    article = create_article
    35.times { |i| ArticleView.create!(article:, edition: "fa", created_at: i.hours.ago) }

    get admin_article_path(article)
    assert_response :success
    assert_select "ul.pagination"

    get admin_article_path(article, page: 2)
    assert_response :success
  end

  test "bulk_rewrite creates a rewrite task for each selected article" do
    OllamaServer.create!(name: "Local", url: "http://localhost:11434",
                         rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b", refine_models: "qwen3:14b")
    one = create_article
    two = create_article

    assert_difference -> { Task.where(kind: "rewrite").count }, 2 do
      post bulk_rewrite_admin_articles_path, params: { article_ids: [ one.id, two.id ] }
    end
    assert_response :redirect
  end

  test "bulk_rewrite with no selection redirects with an alert" do
    post bulk_rewrite_admin_articles_path, params: { article_ids: [] }
    assert_response :redirect
    follow_redirect!
    assert_select ".alert-danger"
  end

  test "bulk_rewrite without a configured server redirects with an alert" do
    article = create_article

    assert_no_difference -> { Task.count } do
      post bulk_rewrite_admin_articles_path, params: { article_ids: [ article.id ] }
    end
    assert_response :redirect
    follow_redirect!
    assert_select ".alert-danger"
  end

  test "bulk_translate creates a translation task for each selected article, falling back to the original when no rewrite exists" do
    OllamaServer.create!(name: "Local", url: "http://localhost:11434",
                         rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b", refine_models: "qwen3:14b")
    with_rewrite    = create_article
    create_rewrite(article: with_rewrite, attrs: { status: "completed" })
    without_rewrite = create_article

    assert_difference -> { Task.where(kind: "translate").count }, 2 do
      post bulk_translate_admin_articles_path, params: { article_ids: [ with_rewrite.id, without_rewrite.id ] }
    end
    assert_response :redirect
  end

  test "bulk_translate with no selection redirects with an alert" do
    post bulk_translate_admin_articles_path, params: { article_ids: [] }
    assert_response :redirect
    follow_redirect!
    assert_select ".alert-danger"
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end
end
