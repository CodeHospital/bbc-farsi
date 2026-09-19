require "test_helper"
require "telegram/bot"

class AutoposterTest < ActiveSupport::TestCase
  test "post_translation queues (but does not deliver) for the feed's configured autopost channel only" do
    target_channel = create_channel(name: "Target", autopost: true)
    other_channel  = create_channel(name: "Other", autopost: true)
    translation    = create_translation_for(channel: target_channel)

    assert_no_telegram_calls { Autoposter.post_translation(translation) }

    assert_equal "pending", TelegramPost.find_by(translation:, telegram_channel: target_channel).status
    assert_nil TelegramPost.find_by(translation:, telegram_channel: other_channel)
  end

  test "post_translation is a no-op for translations that are not completed and active" do
    channel = create_channel(autopost: true)
    translation = create_translation_for(channel:, attrs: { active: false })

    Autoposter.post_translation(translation)

    assert_nil TelegramPost.find_by(translation:, telegram_channel: channel)
  end

  test "post_translation is a no-op when the feed has no autopost channel configured" do
    translation = create_translation(attrs: { status: "completed", active: true }) # default feed: autopost_telegram_channel_id nil

    assert_no_telegram_calls { Autoposter.post_translation(translation) }

    assert_equal 0, TelegramPost.count
  end

  test "post_translation is a no-op when the feed's channel exists but isn't enabled and autopost" do
    disabled_channel   = create_channel(name: "Disabled", enabled: false, autopost: true)
    not_autopost_channel = create_channel(name: "Manual", enabled: true, autopost: false)

    assert_no_telegram_calls do
      Autoposter.post_translation(create_translation_for(channel: disabled_channel))
      Autoposter.post_translation(create_translation_for(channel: not_autopost_channel))
    end

    assert_equal 0, TelegramPost.count
  end

  test "run_all queues newly eligible translations for the feed's autopost channel without delivering them while the channel is cooling down" do
    channel = create_channel(autopost: true)
    # A very recent post keeps the channel outside its delivery window, so run_all's
    # delivery phase must not touch the post this same invocation queues in its first phase.
    TelegramPost.create!(translation: create_translation, telegram_channel: channel,
                          status: "posted", posted_at: Time.current)
    translation = create_translation_for(channel:)

    assert_no_telegram_calls { Autoposter.run_all }

    assert_equal "pending", TelegramPost.find_by(translation:, telegram_channel: channel).status
  end

  test "run_all queues translations from different feeds to their own distinct autopost channels" do
    channel_a = create_channel(name: "Channel A", autopost: true)
    channel_b = create_channel(name: "Channel B", autopost: true)
    # Keep both channels cooling down so run_all's delivery phase (which this
    # test isn't exercising) doesn't also fire real Telegram calls.
    TelegramPost.create!(translation: create_translation, telegram_channel: channel_a,
                          status: "posted", posted_at: Time.current)
    TelegramPost.create!(translation: create_translation, telegram_channel: channel_b,
                          status: "posted", posted_at: Time.current)
    translation_a = create_translation_for(channel: channel_a)
    translation_b = create_translation_for(channel: channel_b)

    assert_no_telegram_calls { Autoposter.run_all }

    assert_equal "pending", TelegramPost.find_by(translation: translation_a, telegram_channel: channel_a).status
    assert_equal "pending", TelegramPost.find_by(translation: translation_b, telegram_channel: channel_b).status
    assert_nil TelegramPost.find_by(translation: translation_a, telegram_channel: channel_b)
    assert_nil TelegramPost.find_by(translation: translation_b, telegram_channel: channel_a)
  end

  test "run_all delivers a newly queued translation immediately when the channel has no posting history yet" do
    channel = create_channel(autopost: true)
    translation = create_translation_for(channel:)

    delivered = stub_telegram_send { Autoposter.run_all }

    assert_equal 1, delivered
    assert_equal "posted", TelegramPost.find_by(translation:, telegram_channel: channel).status
  end

  test "run_all delivers a due queued post and enforces the cooldown before delivering another" do
    channel = create_channel(autopost: false) # delivery sweep covers every enabled channel, not just autopost ones
    translation = create_translation(attrs: { status: "completed", active: true })
    Publisher.post_to_channel(translation, channel)

    delivered = stub_telegram_send { Autoposter.run_all }
    assert_equal 1, delivered
    assert_equal "posted", TelegramPost.find_by(translation:, telegram_channel: channel).status

    another_translation = create_translation(attrs: { status: "completed", active: true })
    Publisher.post_to_channel(another_translation, channel)

    delivered_again = stub_telegram_send { Autoposter.run_all }
    assert_equal 0, delivered_again
    assert_equal "pending", TelegramPost.find_by(translation: another_translation, telegram_channel: channel).status
  end

  test "ready? is true with no prior post, false right after one, true once MIN_INTERVAL+JITTER has passed" do
    channel = create_channel

    assert Autoposter.ready?(channel)

    TelegramPost.create!(translation: create_translation, telegram_channel: channel,
                          status: "posted", posted_at: Time.current)
    assert_not Autoposter.ready?(channel)

    travel (Autoposter::MIN_INTERVAL + Autoposter::JITTER + 1.minute) do
      assert Autoposter.ready?(channel)
    end
  end

  private

  # A completed, active translation whose article's feed is configured to
  # autopost to `channel` (Feed#autopost_telegram_channel).
  def create_translation_for(channel:, attrs: {})
    feed = create_feed(url: "https://feeds.bbci.co.uk/news/autoposter-test-#{SecureRandom.hex(6)}.rss",
                        autopost_telegram_channel: channel)
    rewrite = create_rewrite(article: create_article(feed:))
    create_translation(rewrite:, attrs: { status: "completed", active: true }.merge(attrs))
  end

  def assert_no_telegram_calls
    ::Telegram::Bot::Client.stub(:new, ->(*) { raise "Telegram should not be called" }) { yield }
  end

  def stub_telegram_send
    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |_opts| Struct.new(:message_id).new(1) }
    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }
    ::Telegram::Bot::Client.stub(:new, fake_bot) { yield }
  end
end
