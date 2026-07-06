require "test_helper"

class Admin::TranslationsControllerTest < ActionDispatch::IntegrationTest
  setup { log_in_as }

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

  test "hide_posted filter excludes translations whose article is posted" do
    visible  = translation_with(title: "Pending article",  article_status: "pending")
    excluded = translation_with(title: "Posted article",   article_status: "posted")

    get admin_translations_path(hide_posted: "1")
    assert_select "a[href=?]", admin_translation_path(visible)
    assert_select "a[href=?]", admin_translation_path(excluded), count: 0
  end

  test "translation rows for posted articles show strikethrough class" do
    translation_with(title: "Posted article", article_status: "posted")
    get admin_translations_path
    assert_select "small.posted-title"
  end

  test "needs_manual_edit filter shows only flagged translations" do
    flagged  = translation_with(title: "Flagged one",   needs_manual_edit: true)
    ordinary = translation_with(title: "Ordinary one",  needs_manual_edit: false)

    get admin_translations_path(needs_manual_edit: "1")
    assert_select "a[href=?]", admin_translation_path(flagged)
    assert_select "a[href=?]", admin_translation_path(ordinary), count: 0
  end

  test "sidebar shows a Needs Edit menu item linking to the flagged queue" do
    get admin_translations_path
    assert_select ".sidebar a[href=?]", admin_translations_path(needs_manual_edit: "1"), text: /Needs Edit/
  end

  test "sidebar Needs Edit badge counts translations flagged for manual edit" do
    translation_with(title: "Flagged A", needs_manual_edit: true)
    translation_with(title: "Flagged B", needs_manual_edit: true)
    translation_with(title: "Not flagged", needs_manual_edit: false)

    get admin_translations_path
    assert_select ".sidebar a[href=?] .badge", admin_translations_path(needs_manual_edit: "1"), text: "2"
  end

  test "sidebar hides the Needs Edit badge when nothing is flagged" do
    translation_with(title: "Not flagged", needs_manual_edit: false)

    get admin_translations_path
    assert_select ".sidebar a[href=?] .badge", admin_translations_path(needs_manual_edit: "1"), count: 0
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

  test "show page offers a refine translation action" do
    translation = translation_with(title: "Alpha")
    get admin_translation_path(translation)
    assert_response :success
    assert_select "form[action=?]", refine_admin_translation_path(translation)
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

  test "show renders edit history with the prior text and the editor's username" do
    editor      = log_in_as(create_editor_user)
    translation = translation_with(title: "Alpha", translated_title: "عنوان قدیمی", translated_body: "متن قدیمی")

    patch admin_translation_path(translation), params: {
      translation: { translated_title: "عنوان جدید", translated_body: "متن جدید" }
    }
    assert_response :redirect

    get admin_translation_path(translation)
    assert_response :success
    assert_select "p", text: "متن قدیمی"
    assert_select ".list-group-item", text: /#{editor.username}/
  end

  test "edits and saves a translation" do
    translation = translation_with(title: "Alpha", translated_title: "عنوان قدیمی", translated_body: "متن قدیمی")

    get edit_admin_translation_path(translation)
    assert_response :success

    patch admin_translation_path(translation), params: {
      translation: {
        translated_title: "عنوان جدید",
        translated_body:  "متن جدید"
      }
    }

    assert_redirected_to admin_translation_path(translation)
    translation.reload
    assert_equal "عنوان جدید", translation.translated_title
    assert_equal "متن جدید", translation.translated_body
  end

  test "bulk_rerun re-creates a translation task for each selected translation using its own model" do
    one = translation_with(title: "Alpha", llm_model: "aya-expanse:32b")
    two = translation_with(title: "Beta",  llm_model: "gemma2:27b")

    assert_difference -> { Task.where(kind: "translate").count }, 2 do
      post bulk_rerun_admin_translations_path, params: { translation_ids: [ one.id, two.id ] }
    end
    assert_response :redirect
  end

  test "bulk_rerun with no selection redirects with an alert" do
    post bulk_rerun_admin_translations_path, params: { translation_ids: [] }
    assert_response :redirect
    follow_redirect!
    assert_select ".alert-danger"
  end

  test "bulk_refine creates a refine task for each selected translation" do
    OllamaServer.create!(name: "Local", url: "http://localhost:11434",
                         rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b", refine_models: "qwen3:14b")
    one = translation_with(title: "Alpha")
    two = translation_with(title: "Beta")

    assert_difference -> { Task.where(kind: "refine").count }, 2 do
      post bulk_refine_admin_translations_path, params: { translation_ids: [ one.id, two.id ] }
    end
    assert_response :redirect
  end

  test "bulk_refine without a configured server redirects with an alert" do
    translation = translation_with(title: "Alpha")

    assert_no_difference -> { Task.where(kind: "refine").count } do
      post bulk_refine_admin_translations_path, params: { translation_ids: [ translation.id ] }
    end
    assert_response :redirect
    follow_redirect!
    assert_select ".alert-danger"
  end

  test "bulk_refine with no selection redirects with an alert" do
    post bulk_refine_admin_translations_path, params: { translation_ids: [] }
    assert_response :redirect
    follow_redirect!
    assert_select ".alert-danger"
  end

  private

  def translation_with(title:, article_status: "pending", **attrs)
    article = create_article(attrs: { title: title, status: article_status })
    rewrite = create_rewrite(article: article)
    create_translation(rewrite: rewrite, attrs: attrs)
  end
end
