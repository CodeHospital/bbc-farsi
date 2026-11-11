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
    feed = create_feed(url: "https://feeds.bbci.co.uk/news/channel-destroy-test.rss", autopost_target_channels: [ channel ])

    channel.destroy!

    assert_empty feed.reload.autopost_target_channels
    assert Feed.exists?(feed.id)
  end

  test "defaults to the telegram provider and rejects unknown providers" do
    assert_equal "telegram", TelegramChannel.new.provider
    assert build_channel(provider: "bale").valid?
    assert_not build_channel(provider: "whatsapp").valid?
  end

  test "a custom provider requires an API base URL, a provider name and a message format" do
    custom_channel = build_channel(provider: "custom")
    assert_not custom_channel.valid?
    assert custom_channel.errors.key?(:api_base_url)
    assert custom_channel.errors.key?(:custom_provider_name)
    assert custom_channel.errors.key?(:message_format)

    assert build_custom_channel.valid?
  end

  test "api_base_url must be an http(s) URL and is normalised without a trailing slash" do
    assert_not build_channel(api_base_url: "ftp://bots.example").valid?
    assert_not build_channel(api_base_url: "not a url").valid?
    assert_equal "https://bots.example/api", build_channel(api_base_url: " https://bots.example/api/ ").api_base_url
    assert_nil build_channel(api_base_url: "  ").api_base_url
  end

  test "message_format only accepts html or plain" do
    assert_not build_custom_channel(message_format: "markdown").valid?
  end

  test "effective API endpoint and message format come from the provider unless overridden" do
    assert_equal "https://api.telegram.org", build_channel.effective_api_base_url
    assert_equal "html", build_channel.effective_message_format
    assert_equal "https://tapi.bale.ai", build_channel(provider: "bale").effective_api_base_url
    assert_equal "plain", build_channel(provider: "bale").effective_message_format
    assert_equal "http://localhost:8081", build_channel(api_base_url: "http://localhost:8081").effective_api_base_url
    assert_equal "https://api.other.example", build_custom_channel.effective_api_base_url
    assert_equal "html", build_custom_channel(message_format: "html").effective_message_format
  end

  test "a preset provider ignores a stored message_format" do
    assert_equal "plain", build_channel(provider: "bale", message_format: "html").effective_message_format
  end

  test "poster: Telegram keeps its client, every other provider goes through BotApiPoster" do
    assert_instance_of TelegramPoster, build_channel.poster
    assert_instance_of BotApiPoster, build_channel(provider: "bale").poster
    assert_instance_of BotApiPoster, build_custom_channel.poster
  end

  test "display names leave Telegram bare and mark every other provider" do
    assert_equal "Ch", build_channel.display_name
    assert_equal "Ch (Bale)", build_channel(provider: "bale").display_name
    assert_equal "Ch (بله)", build_channel(provider: "bale").persian_display_name
    assert_equal "Ch (Other Messenger)", build_custom_channel.display_name
    assert_equal "Ch (Other Messenger)", build_custom_channel.persian_display_name
  end

  test "a channel can switch provider even while feeds autopost to it" do
    channel = create_channel
    feed = create_feed(autopost_target_channels: [ channel ])

    assert channel.update(provider: "bale")
    assert_equal [ channel ], feed.reload.autopost_target_channels
  end


  test "WhatsApp requires the sender's phone-number ID and uses the WhatsApp poster" do
    channel = build_channel(provider: "whatsapp", channel_id: "+491701234567")
    assert_not channel.valid?
    assert channel.errors[:account_id].any?

    channel.account_id = "106540352242922"
    assert channel.valid?
    assert_instance_of WhatsappPoster, channel.poster
    assert_equal "https://graph.facebook.com/v23.0", channel.effective_api_base_url
    assert_equal "#{channel.name} (WhatsApp)", channel.display_name
  end

  test "Instagram uses the Instagram poster and requires images" do
    channel = build_channel(provider: "instagram", channel_id: "17841400000000000")
    assert channel.valid?
    assert_instance_of InstagramPoster, channel.poster
    assert channel.requires_image?
  end

  test "TikTok requires app credentials but no channel id" do
    channel = build_channel(provider: "tiktok", channel_id: nil)
    assert_not channel.valid?
    assert channel.errors[:client_key].any?
    assert channel.errors[:client_secret].any?

    channel.assign_attributes(client_key: "key", client_secret: "secret")
    assert channel.valid?
    assert_instance_of TiktokPoster, channel.poster
    assert_equal "https://open.tiktokapis.com", channel.effective_api_base_url
  end

  test "the TikTok client secret is kept out of version history" do
    channel = create_channel(provider: "tiktok", channel_id: nil, client_key: "key", client_secret: "secret-1")
    channel.update!(client_secret: "secret-2")
    assert channel.versions.none? { |version| version.object.to_s.include?("secret-1") || version.object_changes.to_s.include?("secret") }
  end

  private

  def build_channel(attrs = {})
    TelegramChannel.new({ name: "Ch", token: "t", channel_id: "@ch" }.merge(attrs))
  end

  def build_custom_channel(attrs = {})
    build_channel({ provider: "custom", custom_provider_name: "Other Messenger",
                    api_base_url: "https://api.other.example", message_format: "plain" }.merge(attrs))
  end
end
