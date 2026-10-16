require "test_helper"

class Admin::TelegramPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    log_in_as
    @channel = create_channel(name: "News Channel")
  end

  test "scheduled tab lists queued posts in delivery order with an estimate" do
    normal_post = TelegramPost.create!(translation: create_translation(attrs: { translated_title: "عادی" }),
                                       telegram_channel: @channel, status: "pending")
    front_post  = TelegramPost.create!(translation: create_translation(attrs: { translated_title: "فوری" }),
                                       telegram_channel: @channel, status: "pending", priority: 3)
    TelegramPost.create!(translation: create_translation(attrs: { translated_title: "ارسال شده" }),
                         telegram_channel: @channel, status: "posted", posted_at: 5.minutes.ago)

    get admin_telegram_posts_path
    assert_response :success
    assert_select "a.nav-link.active", text: /Scheduled/
    assert_match "فوری", response.body
    assert_match "عادی", response.body
    assert_no_match "ارسال شده", response.body
    assert_operator response.body.index("فوری"), :<, response.body.index("عادی")
    assert_select "a[href=?]", admin_telegram_post_path(front_post)
    assert_select "a[href=?]", admin_telegram_post_path(normal_post)
  end

  test "scheduled tab flags a disabled channel as paused" do
    @channel.update!(enabled: false)
    TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "pending")

    get admin_telegram_posts_path(view: "scheduled")
    assert_response :success
    assert_match "Channel disabled", response.body
  end

  test "history tab lists posted and failed posts, filterable by status and channel" do
    other_channel = create_channel(name: "Other", channel_id: "@other")
    TelegramPost.create!(translation: create_translation(attrs: { translated_title: "موفق" }),
                         telegram_channel: @channel, status: "posted", posted_at: 1.hour.ago)
    TelegramPost.create!(translation: create_translation(attrs: { translated_title: "ناموفق" }),
                         telegram_channel: @channel, status: "error", error_message: "boom")
    TelegramPost.create!(translation: create_translation(attrs: { translated_title: "کانال دیگر" }),
                         telegram_channel: other_channel, status: "posted", posted_at: 2.hours.ago)
    TelegramPost.create!(translation: create_translation(attrs: { translated_title: "در صف" }),
                         telegram_channel: @channel, status: "pending")

    get admin_telegram_posts_path(view: "history")
    assert_response :success
    %w[موفق ناموفق کانال\ دیگر boom].each { |text| assert_match text, response.body }
    assert_no_match "در صف", response.body

    get admin_telegram_posts_path(view: "history", status: "error")
    assert_match "ناموفق", response.body
    assert_no_match "کانال دیگر", response.body

    get admin_telegram_posts_path(view: "history", channel_id: other_channel.id)
    assert_match "کانال دیگر", response.body
    assert_no_match "ناموفق", response.body
  end

  test "history tab supports sorting" do
    TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "posted", posted_at: 1.hour.ago)

    get admin_telegram_posts_path(view: "history", sort: "posted", dir: "asc")
    assert_response :success
  end

  test "show renders a post's details and message" do
    post_record = TelegramPost.create!(translation: create_translation(attrs: { translated_body: "متن پیام" }),
                                       telegram_channel: @channel, status: "error", error_message: "rate limited")

    get admin_telegram_post_path(post_record)
    assert_response :success
    assert_match "متن پیام", response.body
    assert_match "rate limited", response.body
  end
end
