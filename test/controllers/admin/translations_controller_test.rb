require "test_helper"

class Admin::TranslationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
    log_in
  end

  test "lists translations" do
    translation_with(title: "Anything")
    get admin_translations_path
    assert_response :success
  end

  test "filters by status" do
    done = translation_with(title: "Alpha", status: "completed")
    err  = translation_with(title: "Beta",  status: "error")

    get admin_translations_path(status: "error")
    assert_response :success
    assert_select "a[href=?]", admin_translation_path(err)
    assert_select "a[href=?]", admin_translation_path(done), count: 0
  end

  test "filters by model" do
    aya   = translation_with(title: "Alpha", llm_model: "aya-expanse:32b")
    gemma = translation_with(title: "Beta",  llm_model: "gemma2:27b")

    get admin_translations_path(model: "gemma2:27b")
    assert_select "a[href=?]", admin_translation_path(gemma)
    assert_select "a[href=?]", admin_translation_path(aya), count: 0
  end

  test "filters active only" do
    active   = translation_with(title: "Active one",   active: true)
    inactive = translation_with(title: "Inactive one", active: false)

    get admin_translations_path(active: "1")
    assert_select "a[href=?]", admin_translation_path(active)
    assert_select "a[href=?]", admin_translation_path(inactive), count: 0
  end

  test "search matches the article title" do
    match = translation_with(title: "Quantum leap")
    other = translation_with(title: "Sports roundup")

    get admin_translations_path(q: "quantum")
    assert_select "a[href=?]", admin_translation_path(match)
    assert_select "a[href=?]", admin_translation_path(other), count: 0
  end

  test "search matches the Persian translated title" do
    match = translation_with(title: "Alpha", translated_title: "کوانتوم")
    other = translation_with(title: "Beta",  translated_title: "ورزش")

    get admin_translations_path(q: "کوانتوم")
    assert_select "a[href=?]", admin_translation_path(match)
    assert_select "a[href=?]", admin_translation_path(other), count: 0
  end

  test "sorts by article title ascending and descending" do
    translation_with(title: "Zeta article")
    translation_with(title: "Alpha article")

    get admin_translations_path(sort: "article", dir: "asc")
    assert_response :success
    assert_operator response.body.index("Alpha article"), :<, response.body.index("Zeta article")

    get admin_translations_path(sort: "article", dir: "desc")
    assert_operator response.body.index("Zeta article"), :<, response.body.index("Alpha article")
  end

  test "defaults to newest first" do
    older = translation_with(title: "Older item")
    newer = translation_with(title: "Newer item")
    older.update_column(:created_at, 2.days.ago)
    newer.update_column(:created_at, 1.hour.ago)

    get admin_translations_path
    assert_operator response.body.index("Newer item"), :<, response.body.index("Older item")
  end

  test "column headers are sortable and preserve active filters" do
    translation_with(title: "Alpha", status: "completed")

    get admin_translations_path(status: "completed")
    assert_select "thead a[href*='sort=article']"
    assert_select "thead a[href*='sort=model']"
    assert_select "thead a[href*='status=completed']" # filter carried into sort links
  end

  test "active sort column shows a direction indicator" do
    translation_with(title: "Alpha")
    get admin_translations_path(sort: "article", dir: "asc")
    assert_select "thead a", text: /Article ▲/
  end

  test "show page offers a rewrite-the-article action" do
    translation = translation_with(title: "Alpha")
    get admin_translation_path(translation)
    assert_response :success
    assert_select "form[action=?]", rewrite_admin_article_path(translation.article)
  end

  test "rewrite-the-article action creates a rewrite task" do
    OllamaServer.create!(name: "Local", url: "http://localhost:11434",
                         rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b", refine_models: "qwen3:14b")
    translation = translation_with(title: "Alpha")

    assert_difference -> { Task.where(kind: "rewrite").count }, 1 do
      post rewrite_admin_article_path(translation.article)
    end
    assert_response :redirect
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end

  def translation_with(title:, **attrs)
    article = create_article(attrs: { title: title })
    rewrite = create_rewrite(article: article)
    create_translation(rewrite: rewrite, attrs: attrs)
  end
end
