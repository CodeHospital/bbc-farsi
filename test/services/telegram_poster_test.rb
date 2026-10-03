require "test_helper"
require "telegram/bot"

class TelegramPosterTest < ActiveSupport::TestCase
  setup do
    @channel     = TelegramChannel.new(name: "BBC Farsi", token: "123:abc", channel_id: "@bbcfarsi")
    @article     = Article.new(title: "Original English title", url: "https://bbc.co.uk/news/1")
    @translation = Translation.new(
      article:          @article,
      translated_title: "عنوان فارسی",
      translated_body:  "متن فارسی خبر"
    )
  end

  test "sends message to the correct channel with HTML parse mode" do
    sent = nil

    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |opts| sent = opts }

    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    ::Telegram::Bot::Client.stub(:new, fake_bot) do
      TelegramPoster.new.post(translation: @translation, channel: @channel)
    end

    assert_not_nil sent
    assert_equal "@bbcfarsi",  sent[:chat_id]
    assert_equal "HTML",       sent[:parse_mode]
    assert_includes sent[:text], "<b>عنوان فارسی</b>"
  end

  test "escapes HTML-significant characters in LLM-generated text" do
    @translation.translated_title = "خبر <script>&\"مهم\""
    sent = nil

    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |opts| sent = opts }

    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    ::Telegram::Bot::Client.stub(:new, fake_bot) do
      TelegramPoster.new.post(translation: @translation, channel: @channel)
    end

    assert_not_includes sent[:text], "<script>"
    assert_includes sent[:text], CGI.escapeHTML("خبر <script>&\"مهم\"")
  end

  test "message includes bold Persian title" do
    assert_includes actual_message, "<b>عنوان فارسی</b>"
  end

  test "message includes article URL" do
    assert_includes actual_message, "https://bbc.co.uk/news/1"
  end

  test "message includes channel attribution" do
    assert_includes actual_message, "@realbbcfarsi"
  end

  test "connects to the channel's API base URL override (e.g. a self-hosted Bot API server)" do
    @channel.api_base_url = "http://localhost:8081"
    client_arguments = nil
    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |_opts| true }
    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    ::Telegram::Bot::Client.stub(:new, ->(token, **options) { client_arguments = [ token, options ]; fake_bot }) do
      TelegramPoster.new.post(translation: @translation, channel: @channel)
    end

    assert_equal [ "123:abc", { url: "http://localhost:8081" } ], client_arguments
  end

  test "defaults to the official Telegram endpoint" do
    client_options = nil
    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |_opts| true }
    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    ::Telegram::Bot::Client.stub(:new, ->(_token, **options) { client_options = options; fake_bot }) do
      TelegramPoster.new.post(translation: @translation, channel: @channel)
    end

    assert_equal({ url: "https://api.telegram.org" }, client_options)
  end

  private

  # Sends through the real TelegramPoster (stubbing only the Telegram HTTP
  # client) so these assertions exercise actual output instead of a
  # hand-built string that could silently drift from the implementation.
  def actual_message
    sent = nil
    fake_api = Object.new
    fake_api.define_singleton_method(:send_message) { |opts| sent = opts }
    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    ::Telegram::Bot::Client.stub(:new, fake_bot) do
      TelegramPoster.new.post(translation: @translation, channel: @channel)
    end

    sent[:text]
  end
end
