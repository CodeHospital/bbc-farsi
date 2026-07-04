require "test_helper"

class AdminBootstrapTest < ActiveSupport::TestCase
  teardown { %w[ADMIN_USERNAME ADMIN_PASSWORD ADMIN_EMAIL].each { |key| ENV.delete(key) } }

  test "prefers Rails credentials over ENV" do
    ENV["ADMIN_USERNAME"] = "env-username"
    Rails.application.credentials.stub(:dig, ->(key) { "cred-username" if key == :admin_username }) do
      assert_equal "cred-username", AdminBootstrap.username
    end
  end

  test "falls back to ENV when the credential is blank" do
    ENV["ADMIN_EMAIL"] = "env@test.example"
    Rails.application.credentials.stub(:dig, nil) do
      assert_equal "env@test.example", AdminBootstrap.email
    end
  end

  test "configured? is true only once username, password, and email are all present" do
    Rails.application.credentials.stub(:dig, nil) do
      ENV["ADMIN_USERNAME"] = "u"
      ENV["ADMIN_PASSWORD"] = "p"
      assert_not AdminBootstrap.configured?

      ENV["ADMIN_EMAIL"] = "e@test.example"
      assert AdminBootstrap.configured?
    end
  end
end
