# Selects completed, active translations for autopost-enabled Telegram
# channels, and paces *every* channel's actual Telegram deliveries — whether
# a post got queued automatically here or by a human approving it (the web
# admin's "Post" button, the Telegram admin bot's one-tap publish button; see
# Publisher) — to roughly MIN_INTERVAL..MIN_INTERVAL+JITTER apart, so a burst
# of approvals/completions doesn't dump a dozen messages onto a channel
# within seconds — that reads as spam/automation, not an organic news feed.
#
# There's no in-app job queue (background work runs through the external
# Ollama worker / cron, see Gemfile), so delivery is just: on each
# `bbc:autopost` cron tick (every 5 minutes), send at most one due post per
# enabled channel, gated on how long it's been since that channel's last
# `posted_at`. Anything not due yet stays queued (`TelegramPost` status
# "pending") and is picked up on a later tick.
#
# - `post_translation` runs right after a translate task completes (chaining)
#   — queues (does not send) for autopost channels.
# - `run_all` is for the `bbc:autopost` rake task, called by an external
#   scheduler/cron: queues newly-eligible translations for autopost channels,
#   then delivers at most one due post per enabled channel.
class Autoposter
  MIN_INTERVAL = 25.minutes
  JITTER       = 15.minutes # spreads real gaps across ~25-40 min so the cadence doesn't look robotic

  # Queue one translation for every autopost channel it hasn't been queued or
  # posted to yet. Actual delivery happens later — see `run_all`.
  def self.post_translation(translation)
    return unless translation.status == "completed" && translation.active?

    TelegramChannel.autopost.each do |channel|
      Publisher.post_to_channel(translation, channel)
    end
  end

  # Queue newly-eligible translations for autopost channels, then deliver at
  # most one due post per enabled channel (covers autopost-queued posts and
  # ones a human queued via the web admin or the Telegram admin bot alike).
  def self.run_all
    TelegramChannel.autopost.each do |channel|
      Translation.completed.active_version.unposted_for(channel).order(:id).each do |translation|
        Publisher.post_to_channel(translation, channel)
      end
    end

    delivered = 0
    TelegramChannel.enabled.each do |channel|
      next unless ready?(channel)

      result = Publisher.deliver_pending!(channel)
      next unless result

      Rails.logger.error "Autopost delivery failed for post #{result.post&.id}: #{result.message}" unless result.success?
      delivered += 1 if result.success? && result.post.present?
    end

    delivered
  end

  # Whether enough time has passed since the last delivered post on this channel.
  def self.ready?(channel)
    last_posted_at = TelegramPost.posted.where(telegram_channel: channel).maximum(:posted_at)
    return true if last_posted_at.nil?

    Time.current >= last_posted_at + MIN_INTERVAL + rand(JITTER)
  end
end
