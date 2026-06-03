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

  test "sends message to the correct channel with Markdown" do
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
    assert_equal "Markdown",   sent[:parse_mode]
    assert_includes sent[:text], "*عنوان فارسی*"
  end

  test "message includes bold Persian title" do
    assert_includes expected_message, "*عنوان فارسی*"
  end

  test "message includes original English title" do
    assert_includes expected_message, "*Original English title*"
  end

  test "message includes article URL" do
    assert_includes expected_message, "https://bbc.co.uk/news/1"
  end

  test "message includes channel attribution" do
    assert_includes expected_message, "@realbbcfarsi"
  end

  private

  def expected_message
    "📢 *#{@translation.translated_title}*\n\n" \
      "#{@translation.translated_body}\n\n\n" \
      "#{@article.url}\n\n" \
      "follow @realbbcfarsi for more\n\n" \
      "*#{@article.title}*"
  end
end
