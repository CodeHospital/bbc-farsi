require "test_helper"

class TiktokPosterTest < ActiveSupport::TestCase
  TIKTOK_URL   = "https://open.tiktokapis.com".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    stub_article_image_lookup("https://ichef.bbci.co.uk/news/1.jpg")
    @channel = create_channel(name: "Khabarestan TikTok", provider: "tiktok", token: "refresh-old", channel_id: nil,
                              client_key: "app-key", client_secret: "app-secret")
    @article     = create_article(attrs: { url: "https://bbc.co.uk/news/tiktok-1?at_medium=rss" })
    @translation = Translation.new(article: @article, translated_title: "عنوان فارسی", translated_body: "متن فارسی خبر")
  end

  teardown { restore_article_image_lookup }

  test "refreshes the token, saves a rotated refresh token, and direct-posts a photo from our own host" do
    stub_token_refresh(refresh_token: "refresh-new")
    stub_creator_info(%w[FOLLOWER_OF_CREATOR PUBLIC_TO_EVERYONE SELF_ONLY])
    init_payload = nil
    stub_request(:post, "#{TIKTOK_URL}/v2/post/publish/content/init/")
      .with(headers: { "Authorization" => "Bearer access-123" }) { |request| init_payload = JSON.parse(request.body) }
      .to_return(status: 200, body: { data: { publish_id: "p_1" }, error: { code: "ok" } }.to_json, headers: JSON_HEADERS)

    assert_equal({ "publish_id" => "p_1" }, TiktokPoster.new.post(translation: @translation, channel: @channel))

    assert_equal "refresh-new", @channel.reload.token
    assert_equal "PUBLIC_TO_EVERYONE", init_payload["post_info"]["privacy_level"]
    assert_equal "عنوان فارسی", init_payload["post_info"]["title"]
    assert_includes init_payload["post_info"]["description"], "https://bbc.co.uk/news/tiktok-1"
    assert_equal "PHOTO", init_payload["media_type"]
    assert_equal "DIRECT_POST", init_payload["post_mode"]
    assert_equal "PULL_FROM_URL", init_payload["source_info"]["source"]
    assert_equal [ TiktokPoster.public_image_url(@article) ], init_payload["source_info"]["photo_images"]
    assert_match %r{/media/articles/#{@article.id}/image\z}, init_payload["source_info"]["photo_images"].first
  end

  test "falls back to private posting when the app is unaudited" do
    stub_token_refresh
    stub_creator_info(%w[SELF_ONLY])
    init_payload = nil
    stub_request(:post, "#{TIKTOK_URL}/v2/post/publish/content/init/")
      .with { |request| init_payload = JSON.parse(request.body) }
      .to_return(status: 200, body: { data: { publish_id: "p_1" }, error: { code: "ok" } }.to_json, headers: JSON_HEADERS)

    TiktokPoster.new.post(translation: @translation, channel: @channel)
    assert_equal "SELF_ONLY", init_payload["post_info"]["privacy_level"]
    assert_equal "refresh-old", @channel.reload.token
  end

  test "reports a failed token refresh without leaking the secret" do
    stub_request(:post, "#{TIKTOK_URL}/v2/oauth/token/")
      .to_return(status: 400, body: { error: "invalid_grant", error_description: "Refresh token is invalid" }.to_json, headers: JSON_HEADERS)

    error = assert_raises(TiktokPoster::Error) { TiktokPoster.new.post(translation: @translation, channel: @channel) }
    assert_includes error.message, "Refresh token is invalid"
    assert_not_includes error.message, "app-secret"
  end

  test "raises on a TikTok API error reported with HTTP 200" do
    stub_token_refresh
    stub_request(:post, "#{TIKTOK_URL}/v2/post/publish/creator_info/query/")
      .to_return(status: 200, body: { data: {}, error: { code: "spam_risk_too_many_posts", message: "Too many posts" } }.to_json, headers: JSON_HEADERS)

    error = assert_raises(TiktokPoster::Error) { TiktokPoster.new.post(translation: @translation, channel: @channel) }
    assert_includes error.message, "spam_risk_too_many_posts"
  end

  test "refuses an article without an image" do
    stub_article_image_lookup(nil)
    assert_raises(TiktokPoster::Error) { TiktokPoster.new.post(translation: @translation, channel: @channel) }
  end

  private

  def stub_token_refresh(refresh_token: "refresh-old")
    stub_request(:post, "#{TIKTOK_URL}/v2/oauth/token/")
      .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "refresh-old", "client_key" => "app-key"))
      .to_return(status: 200, body: { access_token: "access-123", refresh_token:, expires_in: 86_400 }.to_json, headers: JSON_HEADERS)
  end

  def stub_creator_info(privacy_levels)
    stub_request(:post, "#{TIKTOK_URL}/v2/post/publish/creator_info/query/")
      .to_return(status: 200, body: { data: { privacy_level_options: privacy_levels }, error: { code: "ok" } }.to_json, headers: JSON_HEADERS)
  end
end
