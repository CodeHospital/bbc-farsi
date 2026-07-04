require "test_helper"

class Admin::PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  test "renders the forgot-password form" do
    get new_admin_password_reset_path
    assert_response :success
  end

  test "create sends a reset email for a known active email" do
    user = create_admin_user

    assert_emails 1 do
      post admin_password_resets_path, params: { email: user.email }
    end
    assert_redirected_to admin_login_path
  end

  test "create is a no-op but redirects the same way for an unknown email" do
    assert_no_emails do
      post admin_password_resets_path, params: { email: "nobody@test.example" }
    end
    assert_redirected_to admin_login_path
  end

  test "create does not email a disabled user" do
    user = create_admin_user(active: false)
    assert_no_emails do
      post admin_password_resets_path, params: { email: user.email }
    end
  end

  test "edit renders the reset form for a valid token" do
    user  = create_admin_user
    token = user.generate_token_for(:password_reset)

    get edit_admin_password_reset_path(token)
    assert_response :success
  end

  test "edit redirects for an invalid token" do
    get edit_admin_password_reset_path("bogus-token")
    assert_redirected_to new_admin_password_reset_path
  end

  test "update sets a new password that can then be used to log in" do
    user  = create_admin_user
    token = user.generate_token_for(:password_reset)

    patch admin_password_reset_path(token), params: {
      user: { password: "brandnewpass1", password_confirmation: "brandnewpass1" }
    }
    assert_redirected_to admin_login_path
    assert_equal user, User.authenticate(user.username, "brandnewpass1")
  end

  test "update rejects a mismatched confirmation" do
    user  = create_admin_user
    token = user.generate_token_for(:password_reset)

    patch admin_password_reset_path(token), params: {
      user: { password: "brandnewpass1", password_confirmation: "somethingelse" }
    }
    assert_response :unprocessable_entity
  end

  test "the reset token is invalidated once the password changes" do
    user  = create_admin_user
    token = user.generate_token_for(:password_reset)

    patch admin_password_reset_path(token), params: {
      user: { password: "brandnewpass1", password_confirmation: "brandnewpass1" }
    }

    get edit_admin_password_reset_path(token)
    assert_redirected_to new_admin_password_reset_path
  end
end
