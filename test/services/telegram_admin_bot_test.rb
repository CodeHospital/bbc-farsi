require "test_helper"

class TelegramAdminBotTest < ActiveSupport::TestCase
  teardown { restore_telegram_admin_bot_config }

  test "enabled? is false when unconfigured" do
    assert_not TelegramAdminBot.enabled?
  end

  test "enabled? is true once bot_token and chat_id are both set" do
    stub_telegram_admin_bot_config
    assert TelegramAdminBot.enabled?
  end

  test "enabled? is false when only bot_token is set" do
    stub_telegram_admin_bot_config(chat_id: nil)
    assert_not TelegramAdminBot.enabled?
  end

  test "enabled? is false when only chat_id is set" do
    stub_telegram_admin_bot_config(bot_token: nil)
    assert_not TelegramAdminBot.enabled?
  end

  test "client builds a Telegram::Bot::Client with the configured token" do
    stub_telegram_admin_bot_config(bot_token: "the-token")
    client = TelegramAdminBot.client
    assert_instance_of Telegram::Bot::Client, client
    assert_equal "the-token", client.api.token
  end
end
