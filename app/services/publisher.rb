# Single entry point for posting a Translation to a Telegram channel.
#
# Replaces three near-identical create-post/send/update sequences that had
# drifted slightly apart (Autoposter#deliver, TranslationsController
# #post_to_channel, TelegramAdminNotifier#post_to_channel — plan2.md M-4).
# Backed by a unique index on telegram_posts(translation_id,
# telegram_channel_id) so the autopost sweep, the translate/refine task
# chain, and the Telegram admin bot can all fire around the same moment
# without double-posting.
class Publisher
  Result = Struct.new(:success?, :message, :post, keyword_init: true)

  def self.already_posted?(translation, channel)
    TelegramPost.exists?(translation:, telegram_channel: channel, status: "posted")
  end

  def self.post_to_channel(translation, channel)
    new.post_to_channel(translation, channel)
  end

  def post_to_channel(translation, channel)
    post = claim_post!(translation, channel)
    return Result.new(success?: true, message: "Already posted to #{channel.name}.", post: nil) if post.nil?

    TelegramPoster.new.post(translation:, channel:)
    post.update!(status: "posted", posted_at: Time.current)
    translation.article.update!(status: "posted")
    Result.new(success?: true, message: "Posted to #{channel.name}.", post:)
  rescue StandardError => e
    post&.update!(status: "error", error_message: e.message)
    Result.new(success?: false, message: "Posting failed: #{e.message}", post:)
  end

  private

  # Atomically claims the right to post this translation to this channel.
  # Returns nil when there's nothing to do (already posted, or another
  # caller is claiming it right now); otherwise returns the row to post
  # through (reusing a previously-errored row so retries don't pile up
  # duplicates). The unique index is what actually serializes concurrent
  # callers — a losing `create!` raises RecordNotUnique, treated the same as
  # "someone else is handling it".
  def claim_post!(translation, channel)
    existing = TelegramPost.find_by(translation:, telegram_channel: channel)
    return nil if existing && existing.status.in?(%w[posted pending])

    existing || TelegramPost.create!(translation:, telegram_channel: channel, status: "pending")
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
end
