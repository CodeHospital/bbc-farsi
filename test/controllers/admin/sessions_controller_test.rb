require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
  end

  test "renders login page" do
    get admin_login_path
    assert_response :success
  end

  test "login page does not render the admin sidebar menus" do
    get admin_login_path
    assert_response :success
    assert_select "nav.sidebar", false, "login page must not show the admin sidebar menus"
    assert_select "form[action=?]", admin_login_path
  end

  test "redirects to dashboard on valid credentials" do
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
    assert_redirected_to admin_root_path
  end

  test "re-renders login on wrong password" do
    post admin_login_path, params: { username: "testadmin", password: "wrong" }
    assert_response :unprocessable_entity
  end

  test "re-renders login on wrong username" do
    post admin_login_path, params: { username: "hacker", password: "testpass" }
    assert_response :unprocessable_entity
  end

  test "logout clears session and redirects to login" do
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
    delete admin_logout_path
    assert_redirected_to admin_login_path

    get admin_root_path
    assert_redirected_to admin_login_path
  end
end
