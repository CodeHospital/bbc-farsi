require "test_helper"

class Admin::FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USERNAME"] = "testadmin"
    ENV["ADMIN_PASSWORD"] = "testpass"
    @feed = create_feed
    log_in
  end

  test "lists feeds" do
    get admin_feeds_path
    assert_response :success
  end

  test "toggles feed enabled state" do
    assert @feed.enabled
    patch toggle_admin_feed_path(@feed)
    assert_response :redirect
    assert_not @feed.reload.enabled
  end

  test "deletes a feed" do
    assert_difference("Feed.count", -1) do
      delete admin_feed_path(@feed)
    end
    assert_response :redirect
  end

  private

  def log_in
    post admin_login_path, params: { username: "testadmin", password: "testpass" }
  end
end
