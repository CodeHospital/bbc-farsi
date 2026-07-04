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
  end
end
