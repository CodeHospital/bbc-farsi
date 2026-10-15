require "telegram/bot"

# Notifies an admin/editor over Telegram (the separate "admin bot" configured
# via TelegramAdminBot) whenever a translation has been through its "refine"
# (smart-edit) pass and becomes the active version — i.e. news that is ready
# for a human decision. A plain machine translation never triggers this on its
# own; only once TranslationRefiner has run does the result get DMed (see
# Task#complete!). The notification carries an inline keyboard so the admin
# can act directly from Telegram without opening the web admin:
#
#   1. request rewrite        4. publish to a channel (any provider), to all
#                                channels at once, and/or at the top of the queue
#   2. request retranslation  5. publish / unpublish on the news portal
#   3. request refine         6. mark for manual edit by editors
#
# It also includes plain link buttons out to the source article and to the
# story's English/Persian portal pages, so the admin can read it in context
# before deciding.
#
# Option 4 covers every enabled TelegramChannel row on any Telegram-compatible
# provider — Telegram, Bale (bale.ai), custom; non-Telegram ones carry their
# provider as a suffix, e.g. "(بله)", so the admin can tell them apart. When exactly one channel is enabled, option 4's picker is
# skipped — there's nothing to choose, so the button posts straight to that one
# channel in a single tap (callback post:<id>:<channel_id>) instead of opening a
# submenu. It does NOT auto-publish: the admin still taps once to send, keeping
# the human review gate. With zero or several enabled channels, option 4 opens
# the channel picker submenu.
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
      parse_mode: "HTML",
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
    when "postfirst"   then record!(translation, action, actor) { post_to_channel(translation, extra_id, front: true) }
    when "postall"     then record!(translation, action, actor) { post_to_all_channels(translation) }
    when "postallfirst" then record!(translation, action, actor) { post_to_all_channels(translation, front: true) }
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

  def post_to_channel(translation, channel_id, front: false)
    channel = TelegramChannel.find_by(id: channel_id)
    return "Channel not found." unless channel

    Publisher.post_to_channel(translation, channel, front:).message
  end

  def post_to_all_channels(translation, front: false)
    results = Publisher.post_to_all_channels(translation, front:)
    return "No enabled channels." if results.empty?

    destination = front ? "top of the queue" : "the queue"
    "Added to #{destination} on #{results.size} channel(s)."
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

  # HTML parse mode (H-8 from plan2.md): translated_title/translated_body are
  # LLM-generated Persian text that can contain unbalanced Markdown special
  # characters, which would make Telegram reject the whole message under
  # Markdown parse mode. Every interpolated value is escaped.
  def notification_text(translation)
    article = translation.article
    status_line = [
      (translation.needs_manual_edit? ? "📌 در انتظار ویرایش دستی" : nil),
      (translation.archived? ? "🚫 در پورتال منتشر نشده" : "🌍 در پورتال منتشر شده")
    ].compact.join(" | ")

    <<~TEXT.strip
      📰 <b>#{escape(translation.translated_title)}</b>

      #{escape(translation.translated_body.to_s.truncate(BODY_PREVIEW_LENGTH))}

      #{[ status_line, analysis_lines(article) ].compact.join("\n")}

      منبع: #{escape(article.url.to_s.split('?').first)}
    TEXT
  end

  # AI bias/fact analysis of the original article (see ArticleAnalyzer);
  # nil until the article has been analyzed.
  def analysis_lines(article)
    return nil unless article&.analyzed?

    [
      "⚖️ گرایش: چپ #{article.bias_left_percent}٪ | میانه #{article.bias_center_percent}٪ | راست #{article.bias_right_percent}٪",
      "📅 رخ‌داده (واقعیت) #{article.factual_percent}٪ | گمانه‌زنی درباره آینده #{article.speculative_percent}٪"
    ].join("\n")
  end

  def escape(text) = CGI.escapeHTML(text.to_s)

  def refresh_message(callback_query, translation, action)
    translation.reload
    keyboard = action == "channels" ? channel_menu(translation) : main_menu(translation)

    TelegramAdminBot.client.api.edit_message_text(
      chat_id: callback_query.dig("message", "chat", "id"),
      message_id: callback_query.dig("message", "message_id"),
      text: notification_text(translation),
      parse_mode: "HTML",
      reply_markup: keyboard
    )
  rescue StandardError => e
    Rails.logger.error "TelegramAdminNotifier#refresh_message failed: #{e.class}: #{e.message}"
    Sentry.capture_exception(e)
  end

  def answer(callback_query, text)
    TelegramAdminBot.client.api.answer_callback_query(
      callback_query_id: callback_query["id"], text: text.to_s.truncate(200)
    )
  rescue StandardError => e
    Rails.logger.error "TelegramAdminNotifier#answer failed: #{e.class}: #{e.message}"
    Sentry.capture_exception(e)
  end

  def main_menu(translation)
    id = translation.id
    rows = [
      [ button("🔁 درخواست بازنویسی", "rewrite:#{id}"), button("🌐 درخواست ترجمه مجدد", "retranslate:#{id}") ],
      [ button("✨ درخواست ویرایش هوشمند", "refine:#{id}"),
        button(translation.needs_manual_edit? ? "✅ رفع نشانه ویرایش دستی" : "✋ نشانه‌گذاری برای ویرایش دستی", "manual_edit:#{id}") ],
      [ publish_button(translation),
        button(translation.archived? ? "🌍 انتشار در پورتال" : "🚫 لغو انتشار از پورتال", "portal:#{id}") ]
    ]
    rows.concat(queue_rows(translation))
    rows.concat(link_rows(translation))
    keyboard_markup(rows)
  end

  # Extra publishing shortcuts under the main publish button: post to every
  # enabled channel at once, and/or jump the queue instead of joining its end.
  # With a single channel "all channels" is the same as the publish button, so
  # only the "top of queue" shortcut is offered.
  def queue_rows(translation)
    id = translation.id
    enabled_channels = TelegramChannel.enabled.order(:name).to_a
    case enabled_channels.size
    when 0 then []
    when 1 then [ [ button("⏫ انتشار در ابتدای صف", "postfirst:#{id}:#{enabled_channels.first.id}") ] ]
    else
      [ [ button("📢 انتشار در همه کانال‌ها", "postall:#{id}"),
          button("⏫ همه کانال‌ها (ابتدای صف)", "postallfirst:#{id}") ] ]
    end
  end

  # The "publish to a Telegram channel" entry in the main menu. With exactly
  # one enabled channel there's nothing to choose, so this is a direct one-tap
  # post button (`post:<id>:<channel_id>`) — no submenu, and no auto-publish, so
  # the admin still confirms with a single tap. Tapping it only queues the
  # post (see Publisher/Autoposter) — the actual Telegram message goes out on
  # the shared posting schedule, not instantly, so a burst of approvals
  # doesn't dump them all on the channel at once. The button shows "✅ ارسال
  # شد" once actually delivered, "⏳ در صف" while queued and waiting its turn,
  # and re-queues harmlessly if tapped again. With zero or several enabled
  # channels, keep the picker submenu (`channels:<id>`).
  def publish_button(translation)
    enabled_channels = TelegramChannel.enabled.order(:name).to_a
    if enabled_channels.one?
      channel = enabled_channels.first
      label = channel_status_label(translation, channel)
      button(label, "post:#{translation.id}:#{channel.id}")
    else
      button("📤 انتشار در #{channel_picker_target(enabled_channels)}", "channels:#{translation.id}")
    end
  end

  # Names the provider(s) the picker submenu offers, so the main-menu button
  # doesn't promise "Telegram" when other providers' channels are in there too.
  # Built-in providers come first in PROVIDERS order, then custom ones by name.
  def channel_picker_target(enabled_channels)
    provider_order = TelegramChannel::PROVIDERS.keys
    provider_labels = enabled_channels
      .sort_by { |channel| [ provider_order.index(channel.provider) || provider_order.size, channel.provider_persian_label ] }
      .map(&:provider_persian_label).uniq
    return "کانال تلگرام" if provider_labels.empty?

    provider_labels.one? ? "کانال #{provider_labels.first}" : "کانال‌های #{provider_labels.join(' و ')}"
  end

  def channel_status_label(translation, channel)
    if Publisher.already_posted?(translation, channel)
      "✅ ارسال شد به #{channel.persian_display_name}"
    elsif Publisher.already_queued?(translation, channel)
      "⏳ در صف انتشار در #{channel.persian_display_name}"
    else
      "📤 انتشار در #{channel.persian_display_name}"
    end
  end

  # Plain URL buttons (no callback, no notification round-trip) out to the
  # source article and this story's two portal editions — reading context for
  # the admin, not actions. Skips the portal row entirely when the app's
  # public base URL isn't configured (Llmarkt.app_base_url), since a relative
  # URL would be rejected by Telegram.
  def link_rows(translation)
    rows = [ [ link_button("🔗 خبر در منبع اصلی", translation.article.url) ] ]
    if Llmarkt.app_base_url.present?
      rows << [
        link_button("🇬🇧 خبر در پورتال انگلیسی", english_portal_url(translation)),
        link_button("🇮🇷 خبر در پورتال فارسی", persian_portal_url(translation))
      ]
    end
    rows
  end

  def english_portal_url(translation) = "#{Llmarkt.app_base_url}/en/news/#{translation.seo_param}"
  def persian_portal_url(translation) = "#{Llmarkt.app_base_url}/news/#{translation.seo_param}"

  def channel_menu(translation)
    id = translation.id
    rows = TelegramChannel.enabled.order(:name).map do |channel|
      prefix = if Publisher.already_posted?(translation, channel) then "✅ "
      elsif Publisher.already_queued?(translation, channel) then "⏳ "
      else ""
      end
      [ button("#{prefix}#{channel.persian_display_name}", "post:#{id}:#{channel.id}"),
        button("⏫ ابتدای صف", "postfirst:#{id}:#{channel.id}") ]
    end
    rows << [ button("📢 همه کانال‌ها", "postall:#{id}"), button("⏫ همه (ابتدای صف)", "postallfirst:#{id}") ] if rows.size > 1
    rows << [ button("⬅️ بازگشت", "back:#{id}") ]
    keyboard_markup(rows)
  end

  def keyboard_markup(rows) = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: rows)
  def button(text, callback_data) = Telegram::Bot::Types::InlineKeyboardButton.new(text:, callback_data:)
  def link_button(text, url) = Telegram::Bot::Types::InlineKeyboardButton.new(text:, url:)

  def actor_label(callback_query)
    from = callback_query["from"] || {}
    from["username"].presence || from["id"]&.to_s || "unknown"
  end
end
