# Posts completed, active translations to autopost-enabled Telegram channels.
# Replaces the old AutopostJob. Telegram posting needs no Ollama access, so it
# stays inside the Rails app.
#
# - `post_translation` runs right after a translate task completes (chaining).
# - `run_all` is for the `bbc:autopost` rake task, called by an external
#   scheduler/cron to sweep any active translations not yet posted.
class Autoposter
  # Post one translation to every autopost channel it hasn't been posted to.
  def self.post_translation(translation)
    return unless translation.status == "completed" && translation.active?

    poster = TelegramPoster.new
    TelegramChannel.autopost.each do |channel|
      next if already_posted?(translation, channel)

      deliver(poster, translation, channel)
    end
  end

  # Sweep all active completed translations and post any that are unposted.
  def self.run_all
    poster = TelegramPoster.new
    posted = 0

    TelegramChannel.autopost.each do |channel|
      Translation.completed.active_version.unposted_for(channel).each do |translation|
        posted += 1 if deliver(poster, translation, channel)
      end
    end

    posted
  end

  def self.already_posted?(translation, channel)
    translation.telegram_posts.where(telegram_channel: channel, status: "posted").exists?
  end

  def self.deliver(poster, translation, channel)
    post = TelegramPost.create!(translation:, telegram_channel: channel, status: "pending")
    poster.post(translation:, channel:)
    post.update!(status: "posted", posted_at: Time.current)
    translation.article.update!(status: "posted")
    true
  rescue StandardError => e
    post&.update!(status: "error", error_message: e.message)
    Rails.logger.error "Autopost failed for translation #{translation.id}: #{e.message}"
    false
  end
end
