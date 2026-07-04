require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    assert create_admin_user.valid?
  end

  test "invalid without username" do
    user = User.new(email: "someone@test.example", password: TEST_USER_PASSWORD, role: "admin")
    assert_not user.valid?
  end

  test "invalid without email" do
    user = User.new(username: "someone", password: TEST_USER_PASSWORD, role: "admin")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "invalid with a malformed email" do
    user = User.new(username: "someone", email: "not-an-email", password: TEST_USER_PASSWORD, role: "admin")
    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "email must be unique case-insensitively" do
    create_admin_user(email: "shared@test.example")
    duplicate = User.new(username: "someone-else", email: "Shared@Test.Example", password: TEST_USER_PASSWORD, role: "editor")
    assert_not duplicate.valid?
  end

  test "email is normalized to lowercase" do
    user = create_admin_user(email: "MixedCase@Test.Example")
    assert_equal "mixedcase@test.example", user.email
  end

  test "username must be unique case-insensitively" do
    create_admin_user(username: "shared-name")
    duplicate = User.new(username: "Shared-Name", password: TEST_USER_PASSWORD, role: "editor")
    assert_not duplicate.valid?
  end

  test "invalid role is rejected" do
    user = User.new(username: "someone", password: TEST_USER_PASSWORD, role: "superuser")
    assert_not user.valid?
  end

  test "admin? and editor? reflect role" do
    assert create_admin_user.admin?
    assert_not create_admin_user.editor?
    assert create_editor_user.editor?
    assert_not create_editor_user.admin?
  end

  test "authenticate returns the user on matching username and password" do
    user = create_admin_user
    assert_equal user, User.authenticate(user.username, TEST_USER_PASSWORD)
  end

  test "authenticate is case-insensitive on username" do
    user = create_admin_user(username: "MixedCase")
    assert_equal user, User.authenticate("mixedcase", TEST_USER_PASSWORD)
  end

  test "authenticate returns nil on wrong password" do
    user = create_admin_user
    assert_nil User.authenticate(user.username, "wrong password")
  end

  test "authenticate returns nil for a disabled user" do
    user = create_admin_user(active: false)
    assert_nil User.authenticate(user.username, TEST_USER_PASSWORD)
  end

  test "cannot demote the last active admin to editor" do
    admin = create_admin_user
    admin.role = "editor"
    assert_not admin.valid?
    assert_includes admin.errors[:base], "Can't remove the last active admin."
  end

  test "cannot deactivate the last active admin" do
    admin = create_admin_user
    admin.active = false
    assert_not admin.valid?
  end

  test "can demote an admin when another active admin remains" do
    create_admin_user
    second_admin = create_admin_user
    second_admin.role = "editor"
    assert second_admin.valid?
  end
end
