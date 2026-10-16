# Read-only view of each channel's outbound queue for the admin "Scheduled"
# posts page: the pending/sending TelegramPosts in the order Publisher will
# deliver them (priority desc, then oldest first), each with an estimated
# delivery window.
#
# The estimate mirrors Autoposter's pacing: a channel gets its next message
# once MIN_INTERVAL..MIN_INTERVAL+JITTER has passed since its last delivered
# post, so the post at queue position N (0-based) is expected between
#   earliest = max(now, last_posted_at + MIN_INTERVAL) + N * MIN_INTERVAL
#   latest   = max(now, last_posted_at + MIN_INTERVAL + JITTER) + N * (MIN_INTERVAL + JITTER)
# A disabled channel isn't delivered to at all, so its posts get no estimate.
class PostingSchedule
  Entry = Struct.new(:post, :position, :earliest_at, :latest_at, keyword_init: true) do
    def sending? = post.status == "sending"
  end

  ChannelQueue = Struct.new(:channel, :last_posted_at, :entries, keyword_init: true) do
    def paused? = !channel.enabled?
  end

  QUEUED_STATUSES = %w[sending pending].freeze

  def initialize(channel_id: nil, now: Time.current)
    @channel_id = channel_id.presence
    @now        = now
  end

  # One ChannelQueue per channel that has anything queued, ordered by channel name.
  def channel_queues
    queued_posts = TelegramPost.where(status: QUEUED_STATUSES)
                               .includes(:telegram_channel, translation: :article)
    queued_posts = queued_posts.where(telegram_channel_id: @channel_id) if @channel_id

    last_posted_by_channel = TelegramPost.posted
                                         .where(telegram_channel_id: queued_posts.select(:telegram_channel_id))
                                         .group(:telegram_channel_id).maximum(:posted_at)

    queued_posts.group_by(&:telegram_channel).sort_by { |channel, _| channel.name.to_s.downcase }.map do |channel, posts|
      build_queue(channel, posts, last_posted_by_channel[channel.id])
    end
  end

  private

  def build_queue(channel, posts, last_posted_at)
    # A post already being sent goes first; the rest follow Publisher#deliver_pending!'s order.
    ordered_posts = posts.sort_by { |post| [ post.status == "sending" ? 0 : 1, -post.priority.to_i, post.created_at ] }

    entries = ordered_posts.each_with_index.map do |post, position|
      earliest_at, latest_at = estimate_window(channel, last_posted_at, position, post)
      Entry.new(post:, position: position + 1, earliest_at:, latest_at:)
    end

    ChannelQueue.new(channel:, last_posted_at:, entries:)
  end

  def estimate_window(channel, last_posted_at, position, post)
    return [ nil, nil ] unless channel.enabled?
    return [ @now, @now ] if post.status == "sending"

    min_gap = Autoposter::MIN_INTERVAL
    max_gap = Autoposter::MIN_INTERVAL + Autoposter::JITTER
    first_earliest = last_posted_at ? [ @now, last_posted_at + min_gap ].max : @now
    first_latest   = last_posted_at ? [ @now, last_posted_at + max_gap ].max : @now

    [ first_earliest + position * min_gap, first_latest + position * max_gap ]
  end
end
