require "test_helper"
require "telegram/bot"

class Api::TelegramAdminControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_telegram_admin_bot_config(webhook_secret: "the-secret")
    @translation = create_translation(attrs: { needs_manual_edit: false })
  end

  teardown { restore_telegram_admin_bot_config }

  test "a request without the secret token header is rejected" do
    post_webhook(callback_body("manual_edit"), secret: nil)

    assert_response :unauthorized
    assert_not @translation.reload.needs_manual_edit?
  end

  test "a request with the wrong secret token is rejected" do
    post_webhook(callback_body("manual_edit"), secret: "wrong-secret")

    assert_response :unauthorized
    assert_not @translation.reload.needs_manual_edit?
  end

  test "a request with the correct secret token processes the callback_query" do
    fake_bot = build_fake_bot

    ::Telegram::Bot::Client.stub(:new, fake_bot) do
      post_webhook(callback_body("manual_edit"))
    end

    assert_response :ok
    assert @translation.reload.needs_manual_edit?
  end

  test "a webhook body with no callback_query is accepted as a no-op" do
    post "/api/telegram_admin/webhook", params: { update_id: 1 }.to_json,
      headers: { "Content-Type" => "application/json", "X-Telegram-Bot-Api-Secret-Token" => "the-secret" }

    assert_response :ok
  end

  private

  def post_webhook(body, secret: "the-secret")
    headers = { "Content-Type" => "application/json" }
    headers["X-Telegram-Bot-Api-Secret-Token"] = secret if secret
    post "/api/telegram_admin/webhook", params: body, headers: headers
  end

  def callback_body(action)
    {
      update_id: 1,
      callback_query: {
        id: "cbq-1",
        data: "#{action}:#{@translation.id}",
        from: { id: 42, username: "editor1" },
        message: { message_id: 555, chat: { id: "12345" } }
      }
    }.to_json
  end

  def build_fake_bot
    fake_api = Object.new
    fake_api.define_singleton_method(:edit_message_text)     { |_opts| true }
    fake_api.define_singleton_method(:answer_callback_query) { |_opts| true }
    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }
    fake_bot
  end
end
