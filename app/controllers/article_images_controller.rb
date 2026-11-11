# Serves an article's lead image from our own public host:
# GET /media/articles/:id/image
#
# TikTok's Content Posting API only pulls images from URL prefixes verified in
# the TikTok developer portal, and we can't verify the publishers' CDNs — so
# TiktokPoster points TikTok here instead (see TiktokPoster.public_image_url).
#
# Only proxies the image URL already stored on the article (never one taken
# from the request), refuses non-image responses and anything over
# MAX_IMAGE_BYTES, and refuses hosts that resolve to private/internal
# addresses, so it can't be used to reach the internal network.
require "resolv"
require "ipaddr"

class ArticleImagesController < ApplicationController
  MAX_IMAGE_BYTES = 10.megabytes
  REQUEST_TIMEOUT = 10 # seconds

  def show
    article   = Article.find(params[:id])
    image_uri = safe_image_uri(ArticleImageFetcher.stored_image_url(article))
    return head(:not_found) unless image_uri

    response_from_source = HTTParty.get(image_uri.to_s, timeout: REQUEST_TIMEOUT, follow_redirects: false,
                                        headers: { "User-Agent" => "Mozilla/5.0 (compatible; khabarestan/1.0)" })
    content_type = response_from_source.headers["content-type"].to_s.split(";").first.to_s.strip
    image_bytes  = response_from_source.body.to_s

    unless response_from_source.success? && content_type.start_with?("image/") && image_bytes.bytesize <= MAX_IMAGE_BYTES
      return head(:bad_gateway)
    end

    expires_in 1.day, public: true
    send_data image_bytes, type: content_type, disposition: "inline"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue StandardError => e
    Rails.logger.warn "ArticleImagesController: image for article #{params[:id]} failed: #{e.message}"
    head :bad_gateway
  end

  private

  def safe_image_uri(image_url)
    return if image_url.blank?

    image_uri = URI.parse(image_url)
    return unless image_uri.is_a?(URI::HTTP) && image_uri.host.present?

    resolved_addresses = Resolv.getaddresses(image_uri.host)
    return if resolved_addresses.empty?
    return if resolved_addresses.any? { |address| internal_address?(address) }

    image_uri
  rescue URI::InvalidURIError, IPAddr::InvalidAddressError
    nil
  end

  def internal_address?(address)
    ip_address = IPAddr.new(address)
    ip_address.private? || ip_address.loopback? || ip_address.link_local? || ip_address.to_s == "0.0.0.0" || ip_address.to_s == "::"
  end
end
