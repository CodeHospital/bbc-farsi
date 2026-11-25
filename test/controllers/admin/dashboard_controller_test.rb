require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not logged in" do
    get admin_root_path
    assert_redirected_to admin_login_path
  end

  test "renders dashboard when logged in" do
    log_in_as
    get admin_root_path
    assert_response :success
    assert_select "h2", "Dashboard"
    assert_select ".dash-kpi", 4
    assert_select ".viz-day", Admin::DashboardController::ACTIVITY_DAYS
  end

  test "shows all clear when nothing needs attention" do
    log_in_as
    get admin_root_path
    assert_select ".dash-attention", 0
    assert_match "All clear", response.body
  end

  test "lists articles with errors under needs attention" do
    create_article(attrs: { status: "error" })
    log_in_as
    get admin_root_path
    assert_select "a.dash-attention.tone-danger[href=?]", admin_articles_path(status: "error"), text: /Articles with errors/
  end

  test "counts articles ingested in the last 24 hours and lists them as recent" do
    create_article(attrs: { title: "Fresh dashboard article" })
    log_in_as
    get admin_root_path
    assert_select ".dash-kpi", text: /Articles ingested\s*1/
    assert_select ".dash-list .item-title", text: "Fresh dashboard article"
  end

  test "editors do not see admin-only totals" do
    log_in_as(create_editor_user)
    get admin_root_path
    assert_response :success
    assert_select "a.dash-total[href=?]", admin_feeds_path, count: 0
    assert_select "a.dash-total[href=?]", admin_telegram_channels_path, count: 0
    assert_select "a.dash-total[href=?]", admin_articles_path
  end
end
