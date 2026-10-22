namespace :telegram_admin do
  desc "Register this app's /api/telegram_admin/webhook URL with Telegram"
  task set_webhook: :environment do
    abort "TelegramAdminBot is not configured (need a bot token + chat id)." unless TelegramAdminBot.enabled?
    abort "app_base_url / api_base_url is not set in credentials." if AppHosts.api_base_url.blank?
    abort "TelegramAdminBot.webhook_secret is not set — required so Telegram signs callbacks." if TelegramAdminBot.webhook_secret.blank?

    url    = "#{AppHosts.api_base_url}/api/telegram_admin/webhook"
    result = TelegramAdminBot.client.api.set_webhook(
      url:, secret_token: TelegramAdminBot.webhook_secret, allowed_updates: [ "callback_query" ]
    )
    puts result ? "Webhook set to #{url}" : "Failed to set webhook."
  end

  desc "Remove the registered admin-bot webhook"
  task delete_webhook: :environment do
    abort "TelegramAdminBot is not configured (need a bot token + chat id)." unless TelegramAdminBot.enabled?

    result = TelegramAdminBot.client.api.delete_webhook
    puts result ? "Webhook removed." : "Failed to remove webhook."
  end
end
