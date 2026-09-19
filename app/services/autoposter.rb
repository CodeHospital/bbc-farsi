# Selects completed, active translations for feeds configured to autopost
# (see Feed#autopost_telegram_channel), and paces *every* channel's actual
# Telegram deliveries — whether a post got queued automatically here or by a
# human approving it (the web admin's "Post" button, the Telegram admin bot's
# one-tap publish button; see Publisher) — to roughly
# MIN_INTERVAL..MIN_INTERVAL+JITTER apart, so a burst of approvals/completions
# doesn't dump a dozen messages onto a channel within seconds — that reads as
# spam/automation, not an organic news feed.
#
# Each feed targets at most one autopost channel (Feed#autopost_telegram_channel,
# nil by default — "don't autopost this feed's articles"); the channel must
# also still be `enabled` and have its own Autopost toggle on
# (Feed#autoposts? — deliberately a second gate, so a channel's autoposting
# can be paused without editing every feed pointed at it).
#
# There's no in-app job queue (background work runs through the external
# Ollama worker / cron, see Gemfile), so delivery is just: on each
# `bbc:autopost` cron tick (every 5 minutes), send at most one due post per
# enabled channel, gated on how long it's been since that channel's last
# `posted_at`. Anything not due yet stays queued (`TelegramPost` status
# "pending") and is picked up on a later tick.
#
# - `post_translation` runs right after a translate task completes (chaining)
#   — queues (does not send) for the translation's feed's autopost channel.
# - `run_all` is for the `bbc:autopost` rake task, called by an external
#   scheduler/cron: queues newly-eligible translations for every autoposting
#   feed's channel, then delivers at most one due post per enabled channel.
class Autoposter
  MIN_INTERVAL = 25.minutes
  JITTER       = 15.minutes # spreads real gaps across ~25-40 min so the cadence doesn't look robotic

  # Queue this translation for its feed's autopost channel, if configured and
  # not already queued/posted. Actual delivery happens later — see `run_all`.
  def self.post_translation(translation)
    return unless translation.status == "completed" && translation.active?

    feed = translation.article.feed
    return unless feed.autoposts?

    Publisher.post_to_channel(translation, feed.autopost_telegram_channel)
  end

  # Queue newly-eligible translations for every autoposting feed's channel,
  # then deliver at most one due post per enabled channel (covers
  # autopost-queued posts and ones a human queued via the web admin or the
  # Telegram admin bot alike).
  def self.run_all
    Feed.autoposting.includes(:autopost_telegram_channel).find_each do |feed|
      next unless feed.autoposts?

      channel = feed.autopost_telegram_channel
      Translation.completed.active_version.joins(:article)
                 .where(articles: { feed_id: feed.id })
                 .unposted_for(channel).order(:id).each do |translation|
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
