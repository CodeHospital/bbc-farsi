# Posts completed, active translations to autopost-enabled Telegram channels.
# Replaces the old AutopostJob. Telegram posting needs no Ollama access, so it
# stays inside the Rails app. Actual delivery goes through Publisher (M-4),
# which is what keeps this safe to run alongside the task-chain autopost and
# the Telegram admin bot without double-posting.
#
# - `post_translation` runs right after a translate task completes (chaining).
# - `run_all` is for the `bbc:autopost` rake task, called by an external
#   scheduler/cron to sweep any active translations not yet posted.
class Autoposter
  # Post one translation to every autopost channel it hasn't been posted to.
  def self.post_translation(translation)
    return unless translation.status == "completed" && translation.active?

    TelegramChannel.autopost.each do |channel|
      next if Publisher.already_posted?(translation, channel)

      deliver(translation, channel)
    end
  end

  # Sweep all active completed translations and post any that are unposted.
  def self.run_all
    posted = 0

    TelegramChannel.autopost.each do |channel|
      Translation.completed.active_version.unposted_for(channel).each do |translation|
        posted += 1 if deliver(translation, channel)
      end
    end

    posted
  end

  def self.deliver(translation, channel)
    result = Publisher.post_to_channel(translation, channel)
    Rails.logger.error "Autopost failed for translation #{translation.id}: #{result.message}" unless result.success?
    result.success? && result.post.present?
  end
end
