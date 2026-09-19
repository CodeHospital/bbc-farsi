# Single entry point for getting a Translation onto a Telegram channel.
#
# Posting is split into two steps so every trigger — the autopost sweep, the
# translate/refine task chain, the web admin's "Post" button, and the
# Telegram admin bot's one-tap publish button — shares one outbound cadence
# instead of each firing the Telegram API call the instant it's triggered:
#
#   1. `post_to_channel` claims the translation+channel pair (a `pending`
#      TelegramPost row) — this is what every caller above uses, and it
#      returns immediately without talking to Telegram.
#   2. `deliver_pending!` actually calls the Telegram API for the oldest
#      pending post on a channel. Only `Autoposter.run_all` calls this, gated
#      by `Autoposter.ready?` so a channel only receives a message every
#      ~25-40 min — see Autoposter for why. `run_all` itself is driven both by
#      an in-process poll loop (config/initializers/telegram_autopost_scheduler.rb)
#      and, if configured, the external `bbc:autopost` cron entry — safe to
#      run both, see `claim_for_delivery!` below.
#
# Backed by a unique index on telegram_posts(translation_id,
# telegram_channel_id) so concurrent callers claiming the same pair can't
# double-queue it (plan2.md M-4).
class Publisher
  Result = Struct.new(:success?, :message, :post, keyword_init: true)

  def self.already_posted?(translation, channel)
    TelegramPost.exists?(translation:, telegram_channel: channel, status: "posted")
  end

  def self.already_queued?(translation, channel)
    TelegramPost.exists?(translation:, telegram_channel: channel, status: "pending")
  end

  def self.post_to_channel(translation, channel)
    new.post_to_channel(translation, channel)
  end

  def self.deliver_pending!(channel)
    new.deliver_pending!(channel)
  end

  # Queues translation+channel for delivery. Does not call Telegram — see the
  # class comment above for why delivery is a separate, throttled step.
  def post_to_channel(translation, channel)
    existing = TelegramPost.find_by(translation:, telegram_channel: channel)
    case existing&.status
    when "posted"  then return Result.new(success?: true, message: "Already posted to #{channel.name}.", post: nil)
    when "pending" then return Result.new(success?: true, message: "Already queued for #{channel.name}.", post: nil)
    end

    post = claim_post!(translation, channel, existing)
    return Result.new(success?: true, message: "Already queued for #{channel.name}.", post: nil) if post.nil?

    Result.new(success?: true, message: "Queued to post to #{channel.name} — it will go out on the usual posting schedule.", post:)
  end

  # Actually sends the oldest pending post for a channel to Telegram. Returns
  # nil when there's nothing queued (or another concurrent sweep just claimed
  # it first — see `claim_for_delivery!`).
  def deliver_pending!(channel)
    post = TelegramPost.where(telegram_channel: channel, status: "pending").order(:created_at).first
    return nil unless post
    return nil unless claim_for_delivery!(post)

    deliver(post)
  end

  private

  # Flips pending -> sending in one conditional UPDATE (only succeeds if the
  # row is still "pending"), so two delivery sweeps running at once — e.g. the
  # in-process scheduler and an external cron both calling Autoposter.run_all,
  # or multiple Puma workers — can't both send the same queued post.
  def claim_for_delivery!(post)
    TelegramPost.where(id: post.id, status: "pending").update_all(status: "sending") == 1
  end

  def deliver(post)
    translation = post.translation
    TelegramPoster.new.post(translation:, channel: post.telegram_channel)
    post.update!(status: "posted", posted_at: Time.current)
    translation.article.update!(status: "posted")
    Result.new(success?: true, message: "Posted to #{post.telegram_channel.name}.", post:)
  rescue StandardError => e
    Sentry.capture_exception(e)
    post.update!(status: "error", error_message: e.message)
    Result.new(success?: false, message: "Posting failed: #{e.message}", post:)
  end

  # Atomically claims the right to queue this translation for this channel.
  # Returns nil when another caller just claimed it (the unique index is what
  # actually serializes concurrent callers — a losing `create!` raises
  # RecordNotUnique); otherwise returns the row (reusing a previously-errored
  # row so retries don't pile up duplicates).
  def claim_post!(translation, channel, existing)
    return existing.tap { |p| p.update!(status: "pending") } if existing # status was "error"

    TelegramPost.create!(translation:, telegram_channel: channel, status: "pending")
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    Sentry.capture_exception(e)
    nil
  end
end
