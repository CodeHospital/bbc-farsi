class AutopostJob < ApplicationJob
  queue_as :default

  # Called after each new translation and on the recurring cron schedule.
  # Only posts the active translation for each article to autopost channels.
  def perform(translation_id = nil)
    poster   = TelegramPoster.new
    channels = TelegramChannel.autopost

    translations = if translation_id
      Translation.where(id: translation_id, status: "completed", active: true)
    else
      Translation.completed.active_version
    end

    channels.each do |channel|
      translations.unposted_for(channel).each do |translation|
        post = TelegramPost.create!(translation:, telegram_channel: channel, status: "pending")
        poster.post(translation:, channel:)
        post.update!(status: "posted", posted_at: Time.current)
        translation.article.update!(status: "posted")
      rescue StandardError => e
        post&.update!(status: "error", error_message: e.message)
        Rails.logger.error "AutopostJob failed for translation #{translation.id}: #{e.message}"
      end
    end
  end
end
