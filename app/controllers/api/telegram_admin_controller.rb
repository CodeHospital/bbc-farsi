# Public webhook Telegram calls for the admin notification bot (TelegramAdminBot
# — a separate bot from the per-channel publishing bots in TelegramChannel).
#
# Registered via `bin/rails telegram_admin:set_webhook` (see
# lib/tasks/telegram_admin.rake), which passes `secret_token:` so Telegram
# echoes it back on every request as the X-Telegram-Bot-Api-Secret-Token
# header — verified (constant-time) before any processing, since this endpoint
# has no other auth (unlike /api/tasks, which uses the worker bearer token).
#
#   POST /api/telegram_admin/webhook
#   X-Telegram-Bot-Api-Secret-Token: <TelegramAdminBot.webhook_secret>
#   body: a Telegram Update object (we only act on `callback_query`)
class Api::TelegramAdminController < ActionController::API
  before_action :verify_secret_token!

  def webhook
    handle_callback_query(params[:callback_query]) if params[:callback_query].present?
    head :ok
  end

  private

  def verify_secret_token!
    provided = request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s
    expected = TelegramAdminBot.webhook_secret.to_s

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end

  def handle_callback_query(callback_query)
    TelegramAdminNotifier.handle_callback(callback_query.to_unsafe_h)
  rescue StandardError => e
    Rails.logger.error "Telegram admin webhook error: #{e.class}: #{e.message}"
  end
end
