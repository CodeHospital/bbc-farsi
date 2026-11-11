# Publishes a translated article as an Instagram image post through the
# Instagram Graph API (content publishing):
#
#   1. POST <graph>/<ig-user-id>/media          image_url + caption → container id
#   2. GET  <graph>/<container-id>?fields=status_code   until FINISHED
#   3. POST <graph>/<ig-user-id>/media_publish  creation_id → media id
#
# channel.channel_id is the Instagram professional account ID; channel.token an
# access token with instagram_content_publish (a Meta system-user token does
# not expire). Instagram has no text-only posts, so an article without a lead
# image raises — the post is marked as errored rather than sent.
class InstagramPoster
  MAX_CAPTION_LENGTH = 2200
  CONTAINER_STATUS_CHECKS = 10
  CONTAINER_STATUS_INTERVAL = 3 # seconds between container status checks

  class Error < StandardError; end

  # Overridden in tests so they don't sleep.
  class_attribute :status_check_interval, default: CONTAINER_STATUS_INTERVAL

  def post(translation:, channel:)
    image_url = ArticleImageFetcher.call(translation.article, resolve: true)
    raise Error, "Instagram needs an image, and this article has none." unless image_url

    graph_api = MetaGraphApi.new(channel)
    caption   = SocialPostText.build(translation, max_length: MAX_CAPTION_LENGTH)
    container = graph_api.post("#{channel.channel_id}/media", { image_url:, caption: })

    wait_until_container_ready(graph_api, container.fetch("id"))
    graph_api.post("#{channel.channel_id}/media_publish", { creation_id: container.fetch("id") })
  end

  private

  # Image containers are usually ready at once, but publishing one that is
  # still IN_PROGRESS fails, so check before publishing.
  def wait_until_container_ready(graph_api, container_id)
    CONTAINER_STATUS_CHECKS.times do |check_index|
      status_code = graph_api.get(container_id, fields: "status_code")["status_code"]
      return if status_code.nil? || status_code == "FINISHED"
      raise Error, "Instagram could not process the image (status #{status_code})." if %w[ERROR EXPIRED].include?(status_code)

      sleep(status_check_interval) if check_index < CONTAINER_STATUS_CHECKS - 1
    end
    raise Error, "Instagram was still processing the image after #{CONTAINER_STATUS_CHECKS} checks."
  end
end
