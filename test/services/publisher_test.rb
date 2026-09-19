require "test_helper"
require "telegram/bot"

class PublisherTest < ActiveSupport::TestCase
  setup do
    @channel     = create_channel
    @translation = create_translation
  end

  test "post_to_channel queues a pending post without calling Telegram or marking the article posted" do
    result = nil
    assert_no_telegram_calls do
      result = Publisher.post_to_channel(@translation, @channel)
    end

    assert result.success?
    assert_includes result.message, "Queued to post to #{@channel.name}"
    post = TelegramPost.find_by(translation: @translation, telegram_channel: @channel)
    assert_equal "pending", post.status
    assert_nil post.posted_at
    assert_not_equal "posted", @translation.article.reload.status
  end

  test "post_to_channel is idempotent when already queued" do
    Publisher.post_to_channel(@translation, @channel)

    result = nil
    assert_no_telegram_calls { result = Publisher.post_to_channel(@translation, @channel) }

    assert result.success?
    assert_includes result.message, "Already queued"
    assert_equal 1, TelegramPost.where(translation: @translation, telegram_channel: @channel).count
  end

  test "post_to_channel reports already posted without re-queuing" do
    Publisher.post_to_channel(@translation, @channel)
    stub_telegram_send { Publisher.deliver_pending!(@channel) }

    result = Publisher.post_to_channel(@translation, @channel)

    assert result.success?
    assert_includes result.message, "Already posted"
  end

  test "deliver_pending! sends the oldest queued post and marks it posted" do
    Publisher.post_to_channel(@translation, @channel)

    result = stub_telegram_send { Publisher.deliver_pending!(@channel) }

    assert result.success?
    post = TelegramPost.find_by(translation: @translation, telegram_channel: @channel)
    assert_equal "posted", post.status
    assert_not_nil post.posted_at
    assert_equal "posted", @translation.article.reload.status
  end

  test "deliver_pending! returns nil when nothing is queued for the channel" do
    assert_nil Publisher.deliver_pending!(@channel)
  end

  test "deliver_pending! marks the post as errored when Telegram raises" do
    Publisher.post_to_channel(@translation, @channel)

    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |_opts| raise "boom" }
    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    result = ::Telegram::Bot::Client.stub(:new, fake_bot) { Publisher.deliver_pending!(@channel) }

    assert_not result.success?
    post = TelegramPost.find_by(translation: @translation, telegram_channel: @channel)
    assert_equal "error", post.status
    assert_includes post.error_message, "boom"
  end

  test "deliver_pending! reports a Telegram send failure to Sentry" do
    Publisher.post_to_channel(@translation, @channel)

    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |_opts| raise "boom" }
    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    captured = nil
    ::Telegram::Bot::Client.stub(:new, fake_bot) do
      Sentry.stub(:capture_exception, ->(e) { captured = e }) { Publisher.deliver_pending!(@channel) }
    end

    assert_kind_of RuntimeError, captured
    assert_equal "boom", captured.message
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
