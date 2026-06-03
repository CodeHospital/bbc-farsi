require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
  end

  test "redirects to login when not logged in" do
    get admin_root_path
    assert_redirected_to admin_login_path
  end

  test "renders dashboard when logged in" do
    log_in
    get admin_root_path
    assert_response :success
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end
end
