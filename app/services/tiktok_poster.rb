# Publishes a translated article as a TikTok photo post through the Content
# Posting API (direct post):
#
#   1. POST /v2/oauth/token/                       refresh token → access token
#   2. POST /v2/post/publish/creator_info/query/   allowed privacy levels
#   3. POST /v2/post/publish/content/init/         photo post, PULL_FROM_URL
#
# TikTok access tokens live 24 hours, so channel.token holds the long-lived
# refresh token instead; TikTok may rotate it on refresh, and the new one is
# saved back. channel.client_key / client_secret are the TikTok app's.
#
# TikTok only pulls images from URL prefixes verified in the TikTok developer
# portal, so the image is served from our own public host
# (ArticleImagesController) rather than the publisher's CDN — verify
# `<app_base_url>/media/` there. TikTok has no text-only posts: an article
# without a lead image raises.
#
# Apps that haven't passed TikTok's audit can only post privately
# (SELF_ONLY); the most public privacy level the creator allows is used.
class TiktokPoster
  REQUEST_TIMEOUT        = 20 # seconds
  MAX_TITLE_LENGTH       = 90
  MAX_DESCRIPTION_LENGTH = 4000
  PRIVACY_PREFERENCE     = %w[PUBLIC_TO_EVERYONE MUTUAL_FOLLOW_FRIENDS FOLLOWER_OF_CREATOR SELF_ONLY].freeze

  class Error < StandardError; end

  def post(translation:, channel:)
    article = translation.article
    raise Error, "TikTok needs an image, and this article has none." unless ArticleImageFetcher.call(article, resolve: true)

    access_token  = refresh_access_token!(channel)
    privacy_level = preferred_privacy_level(channel, access_token)

    api_call(channel, "/v2/post/publish/content/init/", access_token, {
      post_info: {
        title:           translation.translated_title.to_s.strip.truncate(MAX_TITLE_LENGTH),
        description:     description_for(translation),
        privacy_level:,
        disable_comment: false,
        auto_add_music:  true
      },
      source_info: {
        source:            "PULL_FROM_URL",
        photo_cover_index: 0,
        photo_images:      [ public_image_url(article) ]
      },
      post_mode:  "DIRECT_POST",
      media_type: "PHOTO"
    })
  end

  def self.public_image_url(article)
    "#{AppHosts.public_base_url.to_s.chomp('/')}#{Rails.application.routes.url_helpers.article_image_path(article)}"
  end

  private

  def public_image_url(article) = self.class.public_image_url(article)

  def description_for(translation)
    "#{translation.translated_body.to_s.strip}\n\n#{SocialPostText.article_link(translation)}".then do |full_description|
      next full_description if full_description.length <= MAX_DESCRIPTION_LENGTH

      link_suffix = "\n\n#{SocialPostText.article_link(translation)}"
      body_budget = [ MAX_DESCRIPTION_LENGTH - link_suffix.length, 0 ].max
      "#{translation.translated_body.to_s.strip.truncate(body_budget)}#{link_suffix}"
    end
  end

  def refresh_access_token!(channel)
    response = HTTParty.post(
      "#{channel.effective_api_base_url}/v2/oauth/token/",
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: {
        client_key:    channel.client_key,
        client_secret: channel.client_secret,
        grant_type:    "refresh_token",
        refresh_token: channel.token
      },
      timeout: REQUEST_TIMEOUT
    )
    token_payload = response.parsed_response
    unless response.success? && token_payload.is_a?(Hash) && token_payload["access_token"].present?
      error_description = token_payload.is_a?(Hash) ? (token_payload["error_description"].presence || token_payload["error"]) : response.body.to_s.truncate(200)
      raise Error, "TikTok token refresh failed (HTTP #{response.code}): #{error_description}"
    end

    rotated_refresh_token = token_payload["refresh_token"]
    if rotated_refresh_token.present? && rotated_refresh_token != channel.token && channel.persisted?
      # update_columns: no validations/callbacks, and `token` is excluded from
      # PaperTrail anyway.
      channel.update_columns(token: rotated_refresh_token, updated_at: Time.current)
    end
    token_payload["access_token"]
  end

  def preferred_privacy_level(channel, access_token)
    creator_info = api_call(channel, "/v2/post/publish/creator_info/query/", access_token, {})
    allowed_levels = Array(creator_info["privacy_level_options"])
    PRIVACY_PREFERENCE.find { |level| allowed_levels.include?(level) } ||
      allowed_levels.first ||
      raise(Error, "TikTok returned no allowed privacy level for this account.")
  end

  # Returns the response's `data`. TikTok reports errors in `error.code`
  # (anything but "ok"), sometimes with HTTP 200.
  def api_call(channel, path, access_token, payload)
    response = HTTParty.post(
      "#{channel.effective_api_base_url}#{path}",
      headers: { "Authorization" => "Bearer #{access_token}", "Content-Type" => "application/json; charset=UTF-8" },
      body: payload.to_json,
      timeout: REQUEST_TIMEOUT
    )
    response_payload = response.parsed_response
    error_details = response_payload.is_a?(Hash) ? response_payload["error"] : nil
    error_code = error_details.is_a?(Hash) ? error_details["code"] : nil
    return response_payload["data"] || {} if response.success? && response_payload.is_a?(Hash) && (error_code.nil? || error_code == "ok")

    error_description = error_details.is_a?(Hash) ? [ error_code, error_details["message"] ].compact.join(": ") : response.body.to_s.truncate(200)
    raise Error, "TikTok #{path.split('/').reject(&:empty?).last} failed (HTTP #{response.code}): #{error_description}"
  end
end
