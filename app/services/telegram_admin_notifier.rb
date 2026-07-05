require "telegram/bot"

# Notifies an admin/editor over Telegram (the separate "admin bot" configured
# via TelegramAdminBot) whenever a translation finishes processing and becomes
# the active version — i.e. news that is ready for a human decision. The
# notification carries an inline keyboard so the admin can act directly from
# Telegram without opening the web admin:
#
#   1. request rewrite        4. publish to a Telegram channel
#   2. request retranslation  5. publish / unpublish on the news portal
#   3. request refine         6. mark for manual edit by editors
#
# Telegram POSTs the resulting button taps to Api::TelegramAdminController,
# which hands the raw callback_query payload to `handle_callback` below.
# Mirrors the existing LlmarktSubmitter pattern of one service owning both the
# outbound call and the matching inbound callback.
class TelegramAdminNotifier
  BODY_PREVIEW_LENGTH = 500

  def self.notify(translation)
    return unless TelegramAdminBot.enabled?

    new.notify(translation)
  end

  def self.handle_callback(callback_query)
    new.handle_callback(callback_query)
  end

  def notify(translation)
    message = TelegramAdminBot.client.api.send_message(
      chat_id: TelegramAdminBot.chat_id,
      text: notification_text(translation),
      parse_mode: "Markdown",
      reply_markup: main_menu(translation)
    )

    TelegramAdminNotification.create!(
      translation:, chat_id: TelegramAdminBot.chat_id.to_s,
      message_id: message.message_id, status: "sent"
    )
  end

  def handle_callback(callback_query)
    action, translation_id, extra_id = callback_query["data"].to_s.split(":")
    translation = Translation.find_by(id: translation_id)
    return answer(callback_query, "This translation no longer exists.") unless translation

    banner = perform_action(action, translation, extra_id, actor_label(callback_query))
    refresh_message(callback_query, translation, action)
    answer(callback_query, banner)
  end

  private

  def perform_action(action, translation, extra_id, actor)
    case action
    when "rewrite"     then record!(translation, action, actor) { enqueue_rewrite(translation) }
    when "retranslate" then record!(translation, action, actor) { enqueue_retranslate(translation) }
    when "refine"      then record!(translation, action, actor) { enqueue_refine(translation) }
    when "post"        then record!(translation, action, actor) { post_to_channel(translation, extra_id) }
    when "portal"      then record!(translation, action, actor) { toggle_portal(translation) }
    when "manual_edit" then record!(translation, action, actor) { toggle_manual_edit(translation) }
    when "channels", "back" then nil # pure navigation — no action to record
    else "Unknown action."
    end
  end

  def record!(translation, action, actor)
    banner = yield
    notification = translation.telegram_admin_notifications.order(created_at: :desc).first
    notification&.update!(status: "actioned", last_action: action, actioned_by: actor, actioned_at: Time.current)
    banner
  end

  # ── Individual actions (mirror the equivalent admin controller actions) ───

  def enqueue_rewrite(translation)
    server, model = OllamaServer.pick(:rewrite)
    return "No Ollama servers with rewrite models configured." unless server

    Task.enqueue_rewrite(translation.article, server:, model:)
    "Rewrite queued (#{model})."
  end

  def enqueue_retranslate(translation)
    Task.enqueue_translate(translation.rewrite, server: translation.ollama_server, model: translation.llm_model)
    "Retranslation queued (#{translation.llm_model})."
  end

  def enqueue_refine(translation)
    server, model = OllamaServer.pick(:refine)
    return "No Ollama servers with refine models configured." unless server

    Task.enqueue_refine(translation, server:, model:)
    "Refine queued (#{model})."
  end

  def post_to_channel(translation, channel_id)
    channel = TelegramChannel.find_by(id: channel_id)
    return "Channel not found." unless channel

    post = TelegramPost.find_or_initialize_by(translation:, telegram_channel: channel)
    TelegramPoster.new.post(translation:, channel:)
    post.update!(status: "posted", posted_at: Time.current)
    translation.article.update!(status: "posted")
    "Posted to #{channel.name}."
  rescue StandardError => e
    post&.update!(status: "error", error_message: e.message)
    "Posting failed: #{e.message}"
  end

  def toggle_portal(translation)
    if translation.archived?
      translation.unarchive!
      "Republished to the news portal."
    else
      translation.archive!
      "Unpublished from the news portal."
    end
  end

  def toggle_manual_edit(translation)
    if translation.needs_manual_edit?
      translation.clear_manual_edit!
      "Manual-edit flag cleared."
    else
      translation.mark_for_manual_edit!
      "Flagged for manual editor review."
    end
  end

  # ── Message rendering ──────────────────────────────────────────────────────

  def notification_text(translation)
    article = translation.article
    status_line = [
      (translation.needs_manual_edit? ? "📌 در انتظار ویرایش دستی" : nil),
      (translation.archived? ? "🚫 در پورتال منتشر نشده" : "🌍 در پورتال منتشر شده")
    ].compact.join(" | ")

    <<~TEXT.strip
      📰 *#{translation.translated_title}*

      #{translation.translated_body.to_s.truncate(BODY_PREVIEW_LENGTH)}

      #{status_line}

      منبع: #{article.url.to_s.split('?').first}
    TEXT
  end

  def refresh_message(callback_query, translation, action)
    translation.reload
    keyboard = action == "channels" ? channel_menu(translation) : main_menu(translation)

    TelegramAdminBot.client.api.edit_message_text(
      chat_id: callback_query.dig("message", "chat", "id"),
      message_id: callback_query.dig("message", "message_id"),
      text: notification_text(translation),
      parse_mode: "Markdown",
      reply_markup: keyboard
    )
  rescue StandardError => e
    Rails.logger.error "TelegramAdminNotifier#refresh_message failed: #{e.class}: #{e.message}"
  end

  def answer(callback_query, text)
    TelegramAdminBot.client.api.answer_callback_query(
      callback_query_id: callback_query["id"], text: text.to_s.truncate(200)
    )
  rescue StandardError => e
    Rails.logger.error "TelegramAdminNotifier#answer failed: #{e.class}: #{e.message}"
  end

  def main_menu(translation)
    id = translation.id
    keyboard_markup([
      [ button("🔁 درخواست بازنویسی", "rewrite:#{id}"), button("🌐 درخواست ترجمه مجدد", "retranslate:#{id}") ],
      [ button("✨ درخواست ویرایش هوشمند", "refine:#{id}"),
        button(translation.needs_manual_edit? ? "✅ رفع نشانه ویرایش دستی" : "✋ نشانه‌گذاری برای ویرایش دستی", "manual_edit:#{id}") ],
      [ button("📤 انتشار در کانال تلگرام", "channels:#{id}"),
        button(translation.archived? ? "🌍 انتشار در پورتال" : "🚫 لغو انتشار از پورتال", "portal:#{id}") ]
    ])
  end

  def channel_menu(translation)
    id = translation.id
    rows = TelegramChannel.enabled.order(:name).map do |channel|
      posted = TelegramPost.exists?(translation:, telegram_channel: channel, status: "posted")
      [ button("#{posted ? '✅ ' : ''}#{channel.name}", "post:#{id}:#{channel.id}") ]
    end
    rows << [ button("⬅️ بازگشت", "back:#{id}") ]
    keyboard_markup(rows)
  end

  def keyboard_markup(rows) = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: rows)
  def button(text, callback_data) = Telegram::Bot::Types::InlineKeyboardButton.new(text:, callback_data:)

  def actor_label(callback_query)
    from = callback_query["from"] || {}
    from["username"].presence || from["id"]&.to_s || "unknown"
  end
end
