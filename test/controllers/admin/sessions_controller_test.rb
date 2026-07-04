require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = create_admin_user }

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
    post admin_login_path, params: { username: @user.username, password: TEST_USER_PASSWORD }
    assert_redirected_to admin_root_path
  end

  test "re-renders login on wrong password" do
    post admin_login_path, params: { username: @user.username, password: "wrong" }
    assert_response :unprocessable_entity
  end

  test "re-renders login on wrong username" do
    post admin_login_path, params: { username: "hacker", password: TEST_USER_PASSWORD }
    assert_response :unprocessable_entity
  end

  test "rejects a disabled user's credentials" do
    editor = create_editor_user(active: false)
    post admin_login_path, params: { username: editor.username, password: TEST_USER_PASSWORD }
    assert_response :unprocessable_entity
  end

  test "logout clears session and redirects to login" do
    post admin_login_path, params: { username: @user.username, password: TEST_USER_PASSWORD }
    delete admin_logout_path
    assert_redirected_to admin_login_path

    get admin_root_path
    assert_redirected_to admin_login_path
  end
end
