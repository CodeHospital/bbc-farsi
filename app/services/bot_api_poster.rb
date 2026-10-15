# Posts a translated article to a channel on any Telegram-compatible bot API
# other than Telegram itself — Bale (bale.ai) or a custom provider — picked by
# TelegramChannel#poster. Calls `<api_base_url>/bot<token>/sendMessage` with
# chat_id + text, the one method every compatible provider implements.
#
# Plain HTTParty rather than telegram-bot-ruby: that gem parses every response
# into strict Telegram types, and a provider-specific field (or a missing one)
# would raise *after* the message was already delivered — marking a successful
# post as failed.
#
# Message format follows TelegramChannel#effective_message_format:
# - "html": same layout as TelegramPoster, parse_mode HTML, bold title.
# - "plain": no parse_mode. For providers without it — Bale always renders its
#   own Markdown, so HTML tags would show up literally.
class BotApiPoster
  MAX_MESSAGE_LENGTH = 4096 # Telegram's limit, which compatible APIs share
  REQUEST_TIMEOUT    = 15   # seconds
  MAX_CAPTION_LENGTH = 1024 # photo caption limit; longer text is sent as a separate message

  class Error < StandardError; end

  def post(translation:, channel:)
    message_text = message_text_for(translation, channel)
    image_url    = ArticleImageFetcher.call(translation.article)

    return call_api(channel, "sendMessage", text_payload(channel, message_text)) unless image_url

    caption_fits = message_text.length <= MAX_CAPTION_LENGTH
    photo_payload = { chat_id: channel.channel_id, photo: image_url }
    photo_payload.merge!(caption_payload(channel, message_text)) if caption_fits

    begin
      photo_result = call_api(channel, "sendPhoto", photo_payload)
    rescue StandardError => photo_error
      # Best-effort: if the provider can't take the photo, the news still goes out as text.
      Rails.logger.warn "BotApiPoster: photo failed for channel #{channel.id}, sending text only: #{photo_error.message}"
      return call_api(channel, "sendMessage", text_payload(channel, message_text))
    end

    caption_fits ? photo_result : call_api(channel, "sendMessage", text_payload(channel, message_text))
  end

  private

  def call_api(channel, api_method, payload)
    response = HTTParty.post(
      "#{channel.effective_api_base_url}/bot#{channel.token}/#{api_method}",
      headers: { "Content-Type" => "application/json" },
      body:    payload.to_json,
      timeout: REQUEST_TIMEOUT
    )

    response_payload = response.parsed_response
    return response_payload["result"] if response.success? && response_payload.is_a?(Hash) && response_payload["ok"]

    # Deliberately never includes the request URL — it carries the bot token,
    # and this message ends up in TelegramPost#error_message on the admin UI.
    error_description = response_payload.is_a?(Hash) ? response_payload["description"] : response.body.to_s.truncate(200)
    raise Error, "#{channel.provider_label} #{api_method} failed (HTTP #{response.code}): #{error_description}"
  end

  def message_text_for(translation, channel)
    channel.effective_message_format == "html" ? html_message(translation, channel) : plain_message(translation, channel)
  end

  def text_payload(channel, message_text)
    { chat_id: channel.channel_id, text: message_text }.merge(parse_mode_payload(channel))
  end

  def caption_payload(channel, message_text)
    { caption: message_text }.merge(parse_mode_payload(channel))
  end

  def parse_mode_payload(channel)
    channel.effective_message_format == "html" ? { parse_mode: "HTML" } : {}
  end

  def plain_message(translation, channel)
    header = "📢 #{translation.translated_title}\n\n"
    footer = "\n\n\n#{article_link(translation)}#{follow_line(channel)}"
    body_budget = MAX_MESSAGE_LENGTH - header.length - footer.length

    "#{header}#{translation.translated_body.to_s.truncate([ body_budget, 0 ].max)}#{footer}"
  end

  def html_message(translation, channel)
    header = "📢 <b>#{escape(translation.translated_title)}</b>\n\n"
    footer = "\n\n\n#{escape(article_link(translation))}#{escape(follow_line(channel))}"
    body_budget = [ MAX_MESSAGE_LENGTH - header.length - footer.length, 0 ].max

    "#{header}#{escaped_body_within(translation.translated_body.to_s, body_budget)}#{footer}"
  end

  # Truncates the *raw* body until its escaped form fits, so an HTML entity
  # (&amp; etc.) is never cut in half — a broken entity makes the provider
  # reject the whole message. Shrinks the raw budget in proportion to how far
  # over the escaped text is (escaping can grow a char up to 6x, e.g. `"` →
  # `&quot;`), always by at least one char so the loop terminates.
  def escaped_body_within(raw_body, budget)
    raw_budget = budget
    loop do
      escaped_body = escape(raw_body.truncate(raw_budget))
      return escaped_body if escaped_body.length <= budget || raw_budget <= 0

      raw_budget = [ raw_budget * budget / escaped_body.length, raw_budget - 1 ].min
    end
  end

  def article_link(translation) = translation.article.url.to_s.split("?").first

  # TelegramPoster's "follow @khabarestan" points at the Telegram channel, so
  # other providers advertise their own channel instead — but only when the
  # channel id is a public @username (a numeric id isn't something to follow).
  def follow_line(channel)
    channel.channel_id.to_s.start_with?("@") ? "\n\nfollow #{channel.channel_id} for more" : ""
  end

  def escape(text) = CGI.escapeHTML(text.to_s)
end
