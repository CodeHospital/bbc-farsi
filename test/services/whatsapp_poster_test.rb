require "test_helper"

class WhatsappPosterTest < ActiveSupport::TestCase
  MESSAGES_URL = "https://graph.facebook.com/v23.0/106540352242922/messages".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    stub_article_image_lookup
    @channel = TelegramChannel.new(name: "Khabarestan WhatsApp", provider: "whatsapp", token: "wa-access-token",
                                   account_id: "106540352242922", channel_id: "+49 170 1234567")
    @article     = Article.new(title: "Original", url: "https://bbc.co.uk/news/1?at_medium=rss")
    @translation = Translation.new(article: @article, translated_title: "عنوان فارسی", translated_body: "متن فارسی خبر")
  end

  teardown { restore_article_image_lookup }

  test "sends a text message to a phone number, with the token only in the Authorization header" do
    sent_payloads = capture_payloads

    assert_equal 1, sent_payloads.size
    sent_payload = sent_payloads.first
    assert_equal "whatsapp", sent_payload["messaging_product"]
    assert_equal "individual", sent_payload["recipient_type"]
    assert_equal "491701234567", sent_payload["to"]
    assert_equal "text", sent_payload["type"]
    assert_includes sent_payload["text"]["body"], "📢 عنوان فارسی"
    assert_includes sent_payload["text"]["body"], "https://bbc.co.uk/news/1"
    assert_not_includes sent_payload["text"]["body"], "at_medium"
    assert_requested(:post, MESSAGES_URL, headers: { "Authorization" => "Bearer wa-access-token" })
  end

  test "a non-phone channel id is sent as a group recipient" do
    @channel.channel_id = "Ab12CdGroupId"
    sent_payload = capture_payloads.first
    assert_equal "group", sent_payload["recipient_type"]
    assert_equal "Ab12CdGroupId", sent_payload["to"]
  end

  test "sends the image with the text as caption when it fits" do
    stub_article_image_lookup("https://ichef.bbci.co.uk/news/1.jpg")
    sent_payloads = capture_payloads

    assert_equal 1, sent_payloads.size
    assert_equal "image", sent_payloads.first["type"]
    assert_equal "https://ichef.bbci.co.uk/news/1.jpg", sent_payloads.first["image"]["link"]
    assert_includes sent_payloads.first["image"]["caption"], "عنوان فارسی"
  end

  test "a long text goes out as the image alone followed by the text" do
    stub_article_image_lookup("https://ichef.bbci.co.uk/news/1.jpg")
    @translation.translated_body = "خ" * 3000
    sent_payloads = capture_payloads

    assert_equal %w[image text], sent_payloads.map { |payload| payload["type"] }
    assert_nil sent_payloads.first["image"]["caption"]
  end

  test "raises with Meta's error message and never leaks the token" do
    stub_request(:post, MESSAGES_URL).to_return(status: 400, headers: JSON_HEADERS,
      body: { error: { message: "Re-engagement message", code: 131047 } }.to_json)

    error = assert_raises(MetaGraphApi::Error) { WhatsappPoster.new.post(translation: @translation, channel: @channel) }
    assert_includes error.message, "Re-engagement message"
    assert_not_includes error.message, "wa-access-token"
  end

  private

  def capture_payloads
    sent_payloads = []
    stub_request(:post, MESSAGES_URL).with { |request| sent_payloads << JSON.parse(request.body) }
      .to_return(status: 200, body: { messages: [ { id: "wamid.1" } ] }.to_json, headers: JSON_HEADERS)
    WhatsappPoster.new.post(translation: @translation, channel: @channel)
    sent_payloads
  end
end
