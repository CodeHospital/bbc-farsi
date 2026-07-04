require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "rejects connection without an admin session" do
    assert_reject_connection { connect }
  end

  test "rejects connection for a user id that doesn't exist" do
    assert_reject_connection { connect session: { user_id: 0 } }
  end

  test "accepts connection when a valid user session is present" do
    key  = SecureRandom.hex(4)
    user = User.create!(username: "cable-#{key}", email: "cable-#{key}@test.example", password: "testpass123", role: "admin")
    connect session: { user_id: user.id }
    assert_equal "admin", connection.current_admin
  end
end
