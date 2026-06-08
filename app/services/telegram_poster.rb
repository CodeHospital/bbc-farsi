require "telegram/bot"
class TelegramPoster
  def post(translation:, channel:)
    bot     = Telegram::Bot::Client.new(channel.token)
    message = build_message(translation)

    bot.api.send_message(
      chat_id:    channel.channel_id,
      text:       message,
      parse_mode: "Markdown"
    )
  end

  private

  def build_message(translation)
    article = translation.article
    "📢 *#{translation.translated_title}*\n\n" \
      "#{translation.translated_body}\n\n\n" \
      "#{article.url.split('?').first}\n\n" \
      "follow @realbbcfarsi for more"
    # "*#{article.title}*"
  end
end
