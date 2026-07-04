require "test_helper"

class Admin::ActivityLogsControllerTest < ActionDispatch::IntegrationTest
  test "editors are redirected away from the activity log (admin-only)" do
    log_in_as(create_editor_user)
    get admin_activity_logs_path
    assert_redirected_to admin_root_path
  end

  test "lists version events with actor and model" do
    admin = log_in_as
    rewrite = create_rewrite

    patch admin_rewrite_path(rewrite), params: { rewrite: { content: "Edited by an admin" } }
    assert_response :redirect

    get admin_activity_logs_path
    assert_response :success
    assert_select "td", text: "Rewrite"
    assert_select "td", text: admin.username
  end

  test "filters by model type" do
    log_in_as
    rewrite = create_rewrite
    rewrite.update!(content: "Changed")
    channel = create_channel
    channel.update!(name: "Renamed channel")

    get admin_activity_logs_path(item_type: "Rewrite")
    assert_response :success
    assert_select "td", text: "Rewrite"
    assert_select "td", text: "TelegramChannel", count: 0
  end
end
