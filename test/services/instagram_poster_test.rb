require "test_helper"

class InstagramPosterTest < ActiveSupport::TestCase
  GRAPH_URL    = "https://graph.facebook.com/v23.0".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    stub_article_image_lookup("https://ichef.bbci.co.uk/news/1.jpg")
    InstagramPoster.status_check_interval = 0
    @channel = TelegramChannel.new(name: "Khabarestan IG", provider: "instagram", token: "ig-token", channel_id: "17841400000000000")
    @article     = Article.new(title: "Original", url: "https://bbc.co.uk/news/1?at_medium=rss")
    @translation = Translation.new(article: @article, translated_title: "عنوان فارسی", translated_body: "متن فارسی خبر")
  end

  teardown do
    restore_article_image_lookup
    InstagramPoster.status_check_interval = InstagramPoster::CONTAINER_STATUS_INTERVAL
  end

  test "creates a media container, waits for it, then publishes it" do
    container_payload = nil
    stub_request(:post, "#{GRAPH_URL}/17841400000000000/media")
      .with { |request| container_payload = JSON.parse(request.body) }
      .to_return(status: 200, body: { id: "container-1" }.to_json, headers: JSON_HEADERS)
    stub_request(:get, "#{GRAPH_URL}/container-1?fields=status_code")
      .to_return({ status: 200, body: { status_code: "IN_PROGRESS" }.to_json, headers: JSON_HEADERS },
                 { status: 200, body: { status_code: "FINISHED" }.to_json, headers: JSON_HEADERS })
    publish_stub = stub_request(:post, "#{GRAPH_URL}/17841400000000000/media_publish")
      .with(body: { creation_id: "container-1" }.to_json, headers: { "Authorization" => "Bearer ig-token" })
      .to_return(status: 200, body: { id: "media-9" }.to_json, headers: JSON_HEADERS)

    assert_equal({ "id" => "media-9" }, InstagramPoster.new.post(translation: @translation, channel: @channel))
    assert_requested publish_stub
    assert_equal "https://ichef.bbci.co.uk/news/1.jpg", container_payload["image_url"]
    assert_includes container_payload["caption"], "📢 عنوان فارسی"
    assert_operator container_payload["caption"].length, :<=, InstagramPoster::MAX_CAPTION_LENGTH
  end

  test "caption is truncated to Instagram's limit" do
    @translation.translated_body = "خ" * 5000
    container_payload = nil
    stub_request(:post, "#{GRAPH_URL}/17841400000000000/media")
      .with { |request| container_payload = JSON.parse(request.body) }
      .to_return(status: 200, body: { id: "container-1" }.to_json, headers: JSON_HEADERS)
    stub_request(:get, "#{GRAPH_URL}/container-1?fields=status_code")
      .to_return(status: 200, body: { status_code: "FINISHED" }.to_json, headers: JSON_HEADERS)
    stub_request(:post, "#{GRAPH_URL}/17841400000000000/media_publish")
      .to_return(status: 200, body: { id: "media-9" }.to_json, headers: JSON_HEADERS)

    InstagramPoster.new.post(translation: @translation, channel: @channel)
    assert_operator container_payload["caption"].length, :<=, InstagramPoster::MAX_CAPTION_LENGTH
    assert container_payload["caption"].end_with?("https://bbc.co.uk/news/1")
  end

  test "refuses an article without an image" do
    stub_article_image_lookup(nil)
    error = assert_raises(InstagramPoster::Error) { InstagramPoster.new.post(translation: @translation, channel: @channel) }
    assert_includes error.message, "image"
  end

  test "raises when Instagram fails to process the image" do
    stub_request(:post, "#{GRAPH_URL}/17841400000000000/media")
      .to_return(status: 200, body: { id: "container-1" }.to_json, headers: JSON_HEADERS)
    stub_request(:get, "#{GRAPH_URL}/container-1?fields=status_code")
      .to_return(status: 200, body: { status_code: "ERROR" }.to_json, headers: JSON_HEADERS)

    assert_raises(InstagramPoster::Error) { InstagramPoster.new.post(translation: @translation, channel: @channel) }
    assert_not_requested :post, "#{GRAPH_URL}/17841400000000000/media_publish"
  end
end
