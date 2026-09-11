# Posts completed, active translations to autopost-enabled Telegram channels.
# Replaces the old AutopostJob. Telegram posting needs no Ollama access, so it
# stays inside the Rails app. Actual delivery goes through Publisher (M-4),
# which is what keeps this safe to run alongside the task-chain autopost and
# the Telegram admin bot without double-posting.
#
# Posts to a given channel are throttled to MIN_INTERVAL (plus a little
# jitter) apart so a burst of translations finishing at once doesn't dump
# them all onto the channel within seconds — that reads as spam/automation.
# There's no in-app job queue (background work runs through the external
# Ollama worker / cron, see Gemfile), so the throttle is just a check against
# the last `posted_at` for the channel: any translation that isn't ready to
# post yet is simply left unposted and picked up by a later `bbc:autopost`
# cron tick (every 5 minutes) once enough time has passed.
#
# - `post_translation` runs right after a translate task completes (chaining).
# - `run_all` is for the `bbc:autopost` rake task, called by an external
#   scheduler/cron to sweep any active translations not yet posted.
class Autoposter
  MIN_INTERVAL = 25.minutes
  JITTER       = 15.minutes # spreads real gaps across ~25-40 min so the cadence doesn't look robotic

  # Post one translation to every autopost channel it hasn't been posted to
  # and that is currently ready (i.e. not still cooling down from its last post).
  def self.post_translation(translation)
    return unless translation.status == "completed" && translation.active?

    TelegramChannel.autopost.each do |channel|
      next if Publisher.already_posted?(translation, channel)
      next unless ready?(channel)

      deliver(translation, channel)
    end
  end

  # Sweep active completed translations and post at most one per autopost
  # channel — whichever channels are ready — per invocation.
  def self.run_all
    posted = 0

    TelegramChannel.autopost.each do |channel|
      next unless ready?(channel)

      translation = Translation.completed.active_version.unposted_for(channel).order(:id).first
      next unless translation

      posted += 1 if deliver(translation, channel)
    end

    posted
  end

  # Whether enough time has passed since the last post to this channel.
  def self.ready?(channel)
    last_posted_at = TelegramPost.posted.where(telegram_channel: channel).maximum(:posted_at)
    return true if last_posted_at.nil?

    Time.current >= last_posted_at + MIN_INTERVAL + rand(JITTER)
  end

  def self.deliver(translation, channel)
    result = Publisher.post_to_channel(translation, channel)
    Rails.logger.error "Autopost failed for translation #{translation.id}: #{result.message}" unless result.success?
    result.success? && result.post.present?
  end
end
