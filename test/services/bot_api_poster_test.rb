require "test_helper"

class BotApiPosterTest < ActiveSupport::TestCase
  setup    { stub_article_image_lookup }
  teardown { restore_article_image_lookup }

  BALE_SEND_URL   = "https://tapi.bale.ai/bot999:bale-token/sendMessage".freeze
  CUSTOM_SEND_URL = "https://bots.other.example/api/bot5:custom-token/sendMessage".freeze
  JSON_HEADERS    = { "Content-Type" => "application/json" }.freeze

  setup do
    @bale_channel   = TelegramChannel.new(name: "Khabarestan Bale", provider: "bale", token: "999:bale-token", channel_id: "@khabarestan_bale")
    @custom_channel = TelegramChannel.new(name: "Other News", provider: "custom", custom_provider_name: "Other Messenger",
                                          api_base_url: "https://bots.other.example/api", message_format: "html",
                                          token: "5:custom-token", channel_id: "@othernews")
    @article     = Article.new(title: "Original English title", url: "https://bbc.co.uk/news/1?at_medium=rss")
    @translation = Translation.new(article: @article, translated_title: "عنوان فارسی", translated_body: "متن فارسی خبر")
  end

  test "Bale: sends a plain-text message (no parse_mode) through Bale's endpoint" do
    sent_payload = capture_payload(BALE_SEND_URL, @bale_channel)

    assert_equal "@khabarestan_bale", sent_payload["chat_id"]
    assert_not sent_payload.key?("parse_mode")
    assert_includes sent_payload["text"], "📢 عنوان فارسی"
    assert_includes sent_payload["text"], "متن فارسی خبر"
    assert_includes sent_payload["text"], "https://bbc.co.uk/news/1"
    assert_not_includes sent_payload["text"], "at_medium"
    assert_not_includes sent_payload["text"], "<b>"
  end

  test "returns the provider's result object on success" do
    stub_request(:post, BALE_SEND_URL)
      .to_return(status: 200, body: { ok: true, result: { message_id: 7 } }.to_json, headers: JSON_HEADERS)

    assert_equal({ "message_id" => 7 }, BotApiPoster.new.post(translation: @translation, channel: @bale_channel))
  end

  test "advertises the channel's own @username, not the Telegram one" do
    sent_text = capture_payload(BALE_SEND_URL, @bale_channel)["text"]
    assert_includes sent_text, "follow @khabarestan_bale for more"
    assert_not_includes sent_text, "follow @khabarestan for more"
  end

  test "omits the follow line for a numeric channel id" do
    @bale_channel.channel_id = "5012345678"
    assert_not_includes capture_payload(BALE_SEND_URL, @bale_channel)["text"], "follow"
  end

  test "plain: truncates the body so the whole message fits the 4096-character limit" do
    @translation.translated_body = "خ" * 10_000
    sent_text = capture_payload(BALE_SEND_URL, @bale_channel)["text"]
    assert_operator sent_text.length, :<=, BotApiPoster::MAX_MESSAGE_LENGTH
    assert sent_text.end_with?("follow @khabarestan_bale for more")
  end

  test "custom provider: posts to its own API base URL with HTML formatting when configured" do
    sent_payload = capture_payload(CUSTOM_SEND_URL, @custom_channel)

    assert_equal "@othernews", sent_payload["chat_id"]
    assert_equal "HTML", sent_payload["parse_mode"]
    assert_includes sent_payload["text"], "<b>عنوان فارسی</b>"
    assert_includes sent_payload["text"], "follow @othernews for more"
  end

  test "custom provider: sends plain text when its message format is plain" do
    @custom_channel.message_format = "plain"
    sent_payload = capture_payload(CUSTOM_SEND_URL, @custom_channel)

    assert_not sent_payload.key?("parse_mode")
    assert_not_includes sent_payload["text"], "<b>"
  end

  test "html: escapes LLM-generated text" do
    @translation.translated_title = "خبر <script>&\"مهم\""
    sent_text = capture_payload(CUSTOM_SEND_URL, @custom_channel)["text"]

    assert_not_includes sent_text, "<script>"
    assert_includes sent_text, CGI.escapeHTML("خبر <script>&\"مهم\"")
  end

  test "html: truncation never splits an HTML entity and the message fits the limit" do
    @translation.translated_body = "&" * 10_000 # every char expands to &amp;
    sent_text = capture_payload(CUSTOM_SEND_URL, @custom_channel)["text"]

    assert_operator sent_text.length, :<=, BotApiPoster::MAX_MESSAGE_LENGTH
    body = sent_text.split("\n\n")[1]
    assert_match(/\A(&amp;)+\.\.\.\z/, body)
  end

  test "raises with the provider's description (and without the bot token) when it rejects the message" do
    stub_request(:post, BALE_SEND_URL)
      .to_return(status: 400, body: { ok: false, error_code: 400, description: "Bad Request: chat not found" }.to_json, headers: JSON_HEADERS)

    error = assert_raises(BotApiPoster::Error) { BotApiPoster.new.post(translation: @translation, channel: @bale_channel) }
    assert_includes error.message, "Bale sendMessage failed"
    assert_includes error.message, "chat not found"
    assert_includes error.message, "HTTP 400"
    assert_not_includes error.message, "bale-token"
  end

  test "raises when the provider answers 200 but ok is false" do
    stub_request(:post, CUSTOM_SEND_URL)
      .to_return(status: 200, body: { ok: false, description: "Forbidden: bot is not an admin" }.to_json, headers: JSON_HEADERS)

    error = assert_raises(BotApiPoster::Error) { BotApiPoster.new.post(translation: @translation, channel: @custom_channel) }
    assert_includes error.message, "Other Messenger sendMessage failed"
  end

  test "Bale: sends a photo with the plain text as caption when the article has an image" do
    photo_url = "https://tapi.bale.ai/bot999:bale-token/sendPhoto"
    stub_request(:post, photo_url).to_return(status: 200, body: { ok: true, result: {} }.to_json, headers: JSON_HEADERS)

    ArticleImageFetcher.stub(:call, "https://ichef.bbci.co.uk/a.jpg") do
      BotApiPoster.new.post(translation: @translation, channel: @bale_channel)
    end

    assert_requested(:post, photo_url) do |request|
      payload = JSON.parse(request.body)
      payload["photo"] == "https://ichef.bbci.co.uk/a.jpg" && payload["caption"].include?("عنوان فارسی") && !payload.key?("parse_mode")
    end
  end

  test "sends photo then full text when over the caption limit, and falls back to text if the photo fails" do
    @translation.translated_body = "خ" * 2000
    photo_url = "https://tapi.bale.ai/bot999:bale-token/sendPhoto"
    stub_request(:post, photo_url).to_return(status: 400, body: { ok: false, description: "bad image" }.to_json, headers: JSON_HEADERS)
    stub_request(:post, BALE_SEND_URL).to_return(status: 200, body: { ok: true, result: {} }.to_json, headers: JSON_HEADERS)

    ArticleImageFetcher.stub(:call, "https://ichef.bbci.co.uk/a.jpg") do
      BotApiPoster.new.post(translation: @translation, channel: @bale_channel)
    end

    assert_requested(:post, photo_url, times: 1)
    assert_requested(:post, BALE_SEND_URL, times: 1)
  end

  private

  def capture_payload(send_url, channel)
    sent_payload = nil
    stub_request(:post, send_url).with { |request| sent_payload = JSON.parse(request.body) }
      .to_return(status: 200, body: { ok: true, result: {} }.to_json, headers: JSON_HEADERS)
    BotApiPoster.new.post(translation: @translation, channel:)
    sent_payload
  end
end
