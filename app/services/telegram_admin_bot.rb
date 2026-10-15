require "telegram/bot"

# Configuration for the Telegram *admin notification* bot — separate from the
# per-channel publishing bots managed at /admin/telegram_channels (TelegramChannel/
# TelegramPoster). This bot DMs an admin/editor chat whenever a translation is
# ready for review, with inline buttons to act on it (see TelegramAdminNotifier).
#
# Read from Rails credentials (see AppCredentials): telegram_admin_bot_token,
# telegram_admin_chat_id, telegram_admin_webhook_secret.
#
# `webhook_secret` is passed as `secret_token:` to Telegram's setWebhook call
# (see lib/tasks/telegram_admin.rake) — Telegram echoes it back on every
# webhook request as the X-Telegram-Bot-Api-Secret-Token header, which
# Api::TelegramAdminController verifies before trusting a callback.
module TelegramAdminBot
  module_function

  def bot_token
    AppCredentials.fetch(:telegram_admin_bot_token).presence
  end

  def chat_id
    AppCredentials.fetch(:telegram_admin_chat_id).presence
  end

  def webhook_secret
    AppCredentials.fetch(:telegram_admin_webhook_secret).presence
  end

  def enabled?
    bot_token.present? && chat_id.present?
  end

  def client
    Telegram::Bot::Client.new(bot_token)
  end
end
