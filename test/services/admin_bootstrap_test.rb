require "test_helper"

class AdminBootstrapTest < ActiveSupport::TestCase
  test "reads the bootstrap admin from Rails credentials" do
    stub_credentials(admin_username: "cred-username", admin_email: "cred@test.example")

    assert_equal "cred-username", AdminBootstrap.username
    assert_equal "cred@test.example", AdminBootstrap.email
  end

  test "ignores ENV" do
    ENV["ADMIN_USERNAME"] = "env-username"
    stub_credentials(admin_username: nil)

    assert_nil AdminBootstrap.username
  ensure
    ENV.delete("ADMIN_USERNAME")
  end

  test "configured? is true only once username, password, and email are all present" do
    stub_credentials(admin_username: "u", admin_password: "p", admin_email: nil)
    assert_not AdminBootstrap.configured?

    stub_credentials(admin_username: "u", admin_password: "p", admin_email: "e@test.example")
    assert AdminBootstrap.configured?
  end
end
