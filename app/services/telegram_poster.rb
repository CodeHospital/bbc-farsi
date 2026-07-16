require "telegram/bot"

# Posts a translated article to a Telegram channel. Uses HTML parse mode
# (H-8 from plan2.md): the title/body are LLM-generated Persian text that can
# freely contain unbalanced *asterisks*, _underscores_, or [brackets], any of
# which makes Telegram reject the whole message under Markdown parse mode.
# HTML mode only cares about `<`/`>`/`&`, which CGI.escapeHTML neutralizes.
class TelegramPoster
  def post(translation:, channel:)
    bot     = Telegram::Bot::Client.new(channel.token)
    message = build_message(translation)

    bot.api.send_message(
      chat_id:    channel.channel_id,
      text:       message,
      parse_mode: "HTML"
    )
  end

  private

  def build_message(translation)
    article = translation.article
    "📢 <b>#{escape(translation.translated_title)}</b>\n\n" \
      "#{escape(translation.translated_body)}\n\n\n" \
      "#{escape(article.url.to_s.split('?').first)}\n\n" \
      "follow @realbbcfarsi for more"
  end

  def escape(text) = CGI.escapeHTML(text.to_s)
end
