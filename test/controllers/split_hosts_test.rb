require "test_helper"

# The app split across khabarestan.com (public), admin.khabarestan.com and
# api.khabarestan.com — see AppHosts / AppRole and config/routes.rb. Routes are
# drawn at boot from the credentials, so each test redraws them with the split
# credentials stubbed in, and teardown redraws the default (non-split) set.
class SplitHostsTest < ActionDispatch::IntegrationTest
  PUBLIC_HOST = "www.khabarestan.com".freeze
  BARE_HOST   = "khabarestan.com".freeze
  ADMIN_HOST  = "admin.khabarestan.com".freeze
  API_HOST    = "api.khabarestan.com".freeze
  WORKER_HOST = "worker.khabarestan.com".freeze

  setup do
    stub_llmarkt_config(app_base_url: "https://#{PUBLIC_HOST}")
    stub_split_hosts(admin_base_url: "https://#{ADMIN_HOST}", api_base_url: "https://#{API_HOST}",
                     worker_base_url: "https://#{WORKER_HOST}")
  end

  teardown do
    ENV.delete("APP_ROLE")
    ENV.delete("LEGACY_API_ON_PUBLIC")
    restore_llmarkt_config
  end

  test "admin UI lives at the root of the admin host" do
    host! ADMIN_HOST
    assert_equal "/", admin_root_path
    assert_equal "/articles", admin_articles_path

    get admin_login_path
    assert_response :success

    log_in_as
    get admin_root_path
    assert_response :success
  end

  test "old /admin URLs on the public host redirect permanently to the admin host" do
    host! PUBLIC_HOST
    get "/admin/articles/5?tab=edit_links"
    assert_response :moved_permanently
    assert_redirected_to "https://#{ADMIN_HOST}/articles/5?tab=edit_links"

    get "/admin"
    assert_redirected_to "https://#{ADMIN_HOST}/"
  end

  test "the bare domain 301-redirects to the canonical www host, keeping path and query" do
    host! BARE_HOST
    get "/news/a12?utm=x"
    assert_response :moved_permanently
    assert_redirected_to "https://#{PUBLIC_HOST}/news/a12?utm=x"

    get "/"
    assert_redirected_to "https://#{PUBLIC_HOST}/"
  end

  test "the worker status page lives at the root of the worker host" do
    assert_equal "/", worker_root_path

    host! WORKER_HOST
    get worker_root_path
    assert_response :success
    assert_select "a[href=?]", worker_login_path

    host! PUBLIC_HOST
    get "/worker"
    assert_response :not_found

    ENV["APP_ROLE"] = "admin"
    host! WORKER_HOST
    get worker_root_path
    assert_response :not_found
  end

  test "worker sign-in shows details with links into the admin host" do
    failed_task = Task.create!(kind: "rewrite", status: "failed", target: create_rewrite, model: "llama3", error_message: "boom")

    host! WORKER_HOST
    post worker_login_path, params: { username: create_admin_user.username, password: TEST_USER_PASSWORD }
    assert_redirected_to worker_root_path

    get worker_root_path
    assert_response :success
    assert_select "a[href=?]", "https://#{ADMIN_HOST}/tasks/#{failed_task.id}"
    assert_match "boom", response.body
  end

  test "the portal and guest edit links only answer on the public host" do
    host! PUBLIC_HOST
    get root_path
    assert_response :success

    edit_link = create_translation.article.edit_links.create!(created_by: create_admin_user, expires_at: 7.days.from_now)
    get guest_edit_path(edit_link.token)
    assert_response :success

    host! ADMIN_HOST
    get news_index_path
    assert_response :not_found
    get guest_edit_path(edit_link.token)
    assert_response :not_found
  end

  test "the worker API answers on the API host only" do
    host! API_HOST
    get api_tasks_next_path
    assert_response :unauthorized

    host! PUBLIC_HOST
    get api_tasks_next_path
    assert_response :not_found

    host! ADMIN_HOST
    get api_tasks_next_path
    assert_response :not_found
  end

  test "LEGACY_API_ON_PUBLIC keeps the worker API on the public host during the move" do
    ENV["LEGACY_API_ON_PUBLIC"] = "1"
    host! PUBLIC_HOST
    get api_tasks_next_path
    assert_response :unauthorized
  end

  test "a container only serves its own APP_ROLE's section" do
    ENV["APP_ROLE"] = "public"
    host! ADMIN_HOST
    get admin_login_path
    assert_response :not_found

    host! PUBLIC_HOST
    get root_path
    assert_response :success

    ENV["APP_ROLE"] = "admin"
    get root_path
    assert_response :not_found
  end

  test "admin pages link to the portal and guest edits on the public host" do
    host! ADMIN_HOST
    admin   = log_in_as
    article = create_article
    article.edit_links.create!(created_by: admin, expires_at: 7.days.from_now)

    get admin_article_path(article)
    assert_response :success
    assert_select "a[href^=?]", "https://#{PUBLIC_HOST}/en/news/"
    assert_select "input[value^=?]", "https://#{PUBLIC_HOST}/edit/"
  end

  test "webhook URLs point at the API host" do
    assert_equal "https://#{API_HOST}", AppHosts.api_base_url
    assert_match %r{\Ahttps://#{API_HOST}/api/llm_callbacks\?token=}, LlmarktSubmitter.callback_url(Task.new(id: 1), "k")
  end
end
