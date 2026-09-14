require "test_helper"
require "telegram/bot"

class AutoposterTest < ActiveSupport::TestCase
  test "post_translation queues (but does not deliver) for autopost channels only" do
    autopost_channel    = create_channel(name: "Autopost", autopost: true)
    non_autopost_channel = create_channel(name: "Manual", autopost: false)
    translation = create_translation(attrs: { status: "completed", active: true })

    assert_no_telegram_calls { Autoposter.post_translation(translation) }

    assert_equal "pending", TelegramPost.find_by(translation:, telegram_channel: autopost_channel).status
    assert_nil TelegramPost.find_by(translation:, telegram_channel: non_autopost_channel)
  end

  test "post_translation is a no-op for translations that are not completed and active" do
    channel = create_channel(autopost: true)
    translation = create_translation(attrs: { status: "completed", active: false })

    Autoposter.post_translation(translation)

    assert_nil TelegramPost.find_by(translation:, telegram_channel: channel)
  end

  test "run_all queues newly eligible translations for autopost channels without delivering them while the channel is cooling down" do
    channel = create_channel(autopost: true)
    # A very recent post keeps the channel outside its delivery window, so run_all's
    # delivery phase must not touch the post this same invocation queues in its first phase.
    TelegramPost.create!(translation: create_translation, telegram_channel: channel,
                          status: "posted", posted_at: Time.current)
    translation = create_translation(attrs: { status: "completed", active: true })

    assert_no_telegram_calls { Autoposter.run_all }

    assert_equal "pending", TelegramPost.find_by(translation:, telegram_channel: channel).status
  end

  test "run_all delivers a newly queued translation immediately when the channel has no posting history yet" do
    channel = create_channel(autopost: true)
    translation = create_translation(attrs: { status: "completed", active: true })

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
