require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "password_reset email is addressed to the user with a reset link" do
    user = create_admin_user
    mail = UserMailer.password_reset(user)

    assert_equal "Reset your BBC Farsi admin password", mail.subject
    assert_equal [ user.email ], mail.to
    assert_match "/admin/password_resets/", mail.body.encoded
  end

  test "password_reset uses a token that resolves back to the user" do
    user = create_admin_user
    UserMailer.password_reset(user)

    token = user.generate_token_for(:password_reset)
    assert_equal user, User.find_by_token_for(:password_reset, token)
  end
end
