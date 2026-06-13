require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "rejects connection without an admin session" do
    assert_reject_connection { connect }
  end

  test "rejects connection when admin_logged_in is false" do
    assert_reject_connection { connect session: { admin_logged_in: false } }
  end

  test "accepts connection when admin session is present" do
    connect session: { admin_logged_in: true }
    assert_equal "admin", connection.current_admin
  end
end
