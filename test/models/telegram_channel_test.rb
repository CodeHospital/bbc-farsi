require "test_helper"

class TelegramChannelTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    assert create_channel.valid?
  end

  test "invalid without name" do
    assert_not build_channel(name: nil).valid?
  end

  test "invalid without token" do
    assert_not build_channel(token: nil).valid?
  end

  test "invalid without channel_id" do
    assert_not build_channel(channel_id: nil).valid?
  end

  test "enabled scope excludes disabled channels" do
    enabled  = create_channel(enabled: true)
    disabled = create_channel(enabled: false)
    assert_includes TelegramChannel.enabled, enabled
    assert_not_includes TelegramChannel.enabled, disabled
  end

  test "autopost scope returns enabled autopost channels only" do
    auto    = create_channel(enabled: true, autopost: true)
    manual  = create_channel(enabled: true, autopost: false)
    assert_includes TelegramChannel.autopost, auto
    assert_not_includes TelegramChannel.autopost, manual
  end

  test "destroying a channel clears it from any feed pointed at it instead of being blocked by the FK" do
    channel = create_channel
    feed = create_feed(url: "https://feeds.bbci.co.uk/news/channel-destroy-test.rss", autopost_telegram_channel: channel)

    channel.destroy!

    assert_nil feed.reload.autopost_telegram_channel_id
  end

  private

  def build_channel(attrs = {})
    TelegramChannel.new({ name: "Ch", token: "t", channel_id: "@ch" }.merge(attrs))
  end
end
