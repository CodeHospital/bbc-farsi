# Posts a translated article through the WhatsApp Business Cloud API:
# `POST <graph>/<phone-number-id>/messages`.
#
# channel.account_id is the sender's phone-number ID; channel.channel_id is the
# recipient — a phone number in international format (digits, optional "+"),
# or a WhatsApp group ID (anything else), sent with recipient_type "group".
#
# WhatsApp only delivers free-form messages to a user inside the 24-hour
# customer-service window (they messaged the business recently); outside it,
# Meta rejects the message and the error lands on the TelegramPost row.
# WhatsApp Channels (the broadcast "newsletters") have no official API.
class WhatsappPoster
  MAX_TEXT_LENGTH    = 4096
  MAX_CAPTION_LENGTH = 1024
  PHONE_NUMBER_RE    = /\A\+?[\d\s\-()]+\z/

  def post(translation:, channel:)
    graph_api    = MetaGraphApi.new(channel)
    message_text = SocialPostText.build(translation, max_length: MAX_TEXT_LENGTH)
    image_url    = ArticleImageFetcher.call(translation.article, resolve: true)

    return send_text(graph_api, channel, message_text) unless image_url

    caption_fits = message_text.length <= MAX_CAPTION_LENGTH
    image_payload = { link: image_url }
    image_payload[:caption] = message_text if caption_fits

    begin
      image_result = send_message(graph_api, channel, type: "image", image: image_payload)
    rescue StandardError => image_error
      # Best-effort: if WhatsApp can't fetch the image, the news still goes out as text.
      Rails.logger.warn "WhatsappPoster: image failed for channel #{channel.id}, sending text only: #{image_error.message}"
      return send_text(graph_api, channel, message_text)
    end

    caption_fits ? image_result : send_text(graph_api, channel, message_text)
  end

  private

  def send_text(graph_api, channel, message_text)
    send_message(graph_api, channel, type: "text", text: { body: message_text, preview_url: true })
  end

  def send_message(graph_api, channel, **message)
    graph_api.post("#{channel.account_id}/messages", {
      messaging_product: "whatsapp",
      recipient_type:    recipient_type(channel),
      to:                recipient(channel)
    }.merge(message))
  end

  def group_recipient?(channel) = !channel.channel_id.to_s.match?(PHONE_NUMBER_RE)
  def recipient_type(channel) = group_recipient?(channel) ? "group" : "individual"
  def recipient(channel) = group_recipient?(channel) ? channel.channel_id : channel.channel_id.to_s.gsub(/\D/, "")
end
