require "telegram/bot"

# Configuration for the Telegram *admin notification* bot — separate from the
# per-channel publishing bots managed at /admin/telegram_channels (TelegramChannel/
# TelegramPoster). This bot DMs an admin/editor chat whenever a translation is
# ready for review, with inline buttons to act on it (see TelegramAdminNotifier).
#
# Credentials are read from Rails credentials first, then ENV as a fallback:
#   credentials.telegram_admin_bot_token      / ENV["TELEGRAM_ADMIN_BOT_TOKEN"]
#   credentials.telegram_admin_chat_id        / ENV["TELEGRAM_ADMIN_CHAT_ID"]
#   credentials.telegram_admin_webhook_secret / ENV["TELEGRAM_ADMIN_WEBHOOK_SECRET"]
#
# `webhook_secret` is passed as `secret_token:` to Telegram's setWebhook call
# (see lib/tasks/telegram_admin.rake) — Telegram echoes it back on every
# webhook request as the X-Telegram-Bot-Api-Secret-Token header, which
# Api::TelegramAdminController verifies before trusting a callback.
module TelegramAdminBot
  module_function

  def bot_token
    fetch(:telegram_admin_bot_token, "TELEGRAM_ADMIN_BOT_TOKEN").presence
  end

  def chat_id
    fetch(:telegram_admin_chat_id, "TELEGRAM_ADMIN_CHAT_ID").presence
  end

  def webhook_secret
    fetch(:telegram_admin_webhook_secret, "TELEGRAM_ADMIN_WEBHOOK_SECRET").presence
  end

  def enabled?
    bot_token.present? && chat_id.present?
  end

  def client
    Telegram::Bot::Client.new(bot_token)
  end

  def fetch(credential_key, env_key)
    Rails.application.credentials.dig(credential_key) || ENV[env_key]
  end
  private_class_method :fetch
end
