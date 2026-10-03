require "test_helper"

class Admin::TelegramChannelsControllerTest < ActionDispatch::IntegrationTest
  setup { log_in_as }

  test "creates a Bale channel" do
    assert_difference(-> { TelegramChannel.where(provider: "bale").count }, 1) do
      post admin_telegram_channels_path, params: { telegram_channel: {
        name: "Bale News", provider: "bale", token: "1:bale", channel_id: "@balenews", enabled: "1"
      } }
    end
    assert_redirected_to admin_telegram_channels_path
  end

  test "index shows each channel's provider" do
    create_channel(name: "Telegram News")
    create_channel(name: "Bale News", provider: "bale", channel_id: "@balenews")

    get admin_telegram_channels_path
    assert_response :success
    assert_select "td", text: "Bale News"
    assert_match "Bale", response.body
    assert_match "Telegram", response.body
  end

  test "new channel form offers every provider plus the custom-provider fields" do
    get new_admin_telegram_channel_path
    assert_response :success
    assert_select "select[name=?]", "telegram_channel[provider]" do
      assert_select "option[value='telegram']"
      assert_select "option[value='bale']"
      assert_select "option[value='custom']"
    end
    assert_select "input[name=?]", "telegram_channel[api_base_url]"
    assert_select "input[name=?]", "telegram_channel[custom_provider_name]"
    assert_select "select[name=?]", "telegram_channel[message_format]"
  end

  test "creates a channel on a custom Telegram-compatible provider" do
    post admin_telegram_channels_path, params: { telegram_channel: {
      name: "Other News", provider: "custom", custom_provider_name: "Other Messenger",
      api_base_url: "https://bots.other.example/", message_format: "plain",
      token: "1:other", channel_id: "@othernews", enabled: "1"
    } }

    assert_redirected_to admin_telegram_channels_path
    channel = TelegramChannel.find_by!(name: "Other News")
    assert channel.custom?
    assert_equal "https://bots.other.example", channel.api_base_url
    assert_equal "Other Messenger", channel.provider_label
  end

  test "rejects a custom provider channel without its API base URL" do
    assert_no_difference("TelegramChannel.count") do
      post admin_telegram_channels_path, params: { telegram_channel: {
        name: "Other News", provider: "custom", custom_provider_name: "Other Messenger", message_format: "plain",
        token: "1:other", channel_id: "@othernews"
      } }
    end
    assert_response :unprocessable_entity
  end
end
