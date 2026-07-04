require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup { @admin = log_in_as }

  test "editors are redirected away from user management (admin-only)" do
    post admin_logout_path
    log_in_as(create_editor_user)

    get admin_users_path
    assert_redirected_to admin_root_path
  end

  test "index lists users" do
    editor = create_editor_user
    get admin_users_path
    assert_response :success
    assert_select "td", text: editor.username
  end

  test "new renders the form" do
    get new_admin_user_path
    assert_response :success
  end

  test "create adds a new editor" do
    assert_difference("User.count", 1) do
      post admin_users_path, params: {
        user: { username: "new-editor", email: "new-editor@test.example", role: "editor", password: "supersecret1", password_confirmation: "supersecret1" }
      }
    end
    assert_response :redirect
    assert User.find_by(username: "new-editor").editor?
  end

  test "create with a blank username re-renders the form" do
    assert_no_difference("User.count") do
      post admin_users_path, params: { user: { username: "", email: "blank-username@test.example", role: "editor", password: "supersecret1", password_confirmation: "supersecret1" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes role and name without touching the password" do
    editor = create_editor_user
    patch admin_user_path(editor), params: { user: { name: "Ed Itor", role: "editor" } }
    assert_response :redirect
    editor.reload
    assert_equal "Ed Itor", editor.name
    assert_equal editor, User.authenticate(editor.username, TEST_USER_PASSWORD)
  end

  test "update with a new password changes the login credential" do
    editor = create_editor_user
    patch admin_user_path(editor), params: {
      user: { role: "editor", password: "brandnewpass1", password_confirmation: "brandnewpass1" }
    }
    assert_response :redirect
    assert_equal editor, User.authenticate(editor.username, "brandnewpass1")
  end

  test "toggle disables and re-enables a user" do
    editor = create_editor_user
    patch toggle_admin_user_path(editor)
    assert_not editor.reload.active?

    patch toggle_admin_user_path(editor)
    assert editor.reload.active?
  end

  test "toggle refuses to disable the last active admin" do
    patch toggle_admin_user_path(@admin)
    assert @admin.reload.active?
  end
end
