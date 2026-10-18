require "telegram/bot"

# Posts a translated article to a Telegram channel. Uses HTML parse mode
# (H-8 from plan2.md): the title/body are LLM-generated Persian text that can
# freely contain unbalanced *asterisks*, _underscores_, or [brackets], any of
# which makes Telegram reject the whole message under Markdown parse mode.
# HTML mode only cares about `<`/`>`/`&`, which CGI.escapeHTML neutralizes.
class TelegramPoster
  # Telegram's limit for a photo caption; longer text goes out as a separate message.
  MAX_CAPTION_LENGTH = 1024

  def post(translation:, channel:)
    # url: honours a per-channel override (e.g. a self-hosted Telegram Bot API
    # server); defaults to api.telegram.org. See TelegramChannel#effective_api_base_url.
    bot       = Telegram::Bot::Client.new(channel.token, url: channel.effective_api_base_url)
    message   = build_message(channel, translation)
    image_url = ArticleImageFetcher.call(translation.article, resolve: true)

    # The photo is best-effort: if the provider can't fetch the image, the news
    # still goes out as text.
    return send_photo_then_text(bot, channel, image_url, message) if image_url

    send_text(bot, channel, message)
  end

  private

  def send_text(bot, channel, message)
    bot.api.send_message(chat_id: channel.channel_id, text: message, parse_mode: "HTML")
  end

  # One photo message with the text as caption when it fits; otherwise the photo
  # alone followed by the full text. Falls back to text only if the photo fails.
  def send_photo_then_text(bot, channel, image_url, message)
    caption_fits = message.length <= MAX_CAPTION_LENGTH
    photo_options = { chat_id: channel.channel_id, photo: image_url }
    photo_options.merge!(caption: message, parse_mode: "HTML") if caption_fits

    begin
      photo_result = bot.api.send_photo(**photo_options)
    rescue StandardError => photo_error
      Rails.logger.warn "TelegramPoster: photo failed for channel #{channel.id}, sending text only: #{photo_error.message}"
      return send_text(bot, channel, message)
    end

    caption_fits ? photo_result : send_text(bot, channel, message)
  end

  def build_message(channel, translation)
    article = translation.article
    "📢 <b>#{escape(translation.translated_title)}</b>\n\n" \
      "#{escape(translation.translated_body)}\n\n\n" \
      "#{escape(article.url.to_s.split('?').first)}\n\n" \
      "follow #{channel.channel_id} for more"
  end

  def escape(text) = CGI.escapeHTML(text.to_s)
end
