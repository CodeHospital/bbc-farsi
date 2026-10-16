require "test_helper"

class PostingScheduleTest < ActiveSupport::TestCase
  setup do
    @channel = create_channel
    @now     = Time.zone.parse("2026-10-16 12:00")
  end

  test "orders queued posts like the publisher and estimates each delivery window" do
    TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "posted", posted_at: @now - 10.minutes)
    older  = TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "pending", created_at: @now - 2.hours)
    newer  = TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "pending", created_at: @now - 1.hour)
    urgent = TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "pending", priority: 1)

    queue = PostingSchedule.new(now: @now).channel_queues.sole
    assert_equal [ urgent, older, newer ], queue.entries.map(&:post)
    assert_equal [ 1, 2, 3 ], queue.entries.map(&:position)

    first, second, = queue.entries
    assert_equal @now + 15.minutes, first.earliest_at # last post 10 min ago + 25 min minimum
    assert_equal @now + 30.minutes, first.latest_at   # + 40 min maximum
    assert_equal first.earliest_at + Autoposter::MIN_INTERVAL, second.earliest_at
    assert_equal first.latest_at + Autoposter::MIN_INTERVAL + Autoposter::JITTER, second.latest_at
  end

  test "a channel that has never posted is due immediately" do
    TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "pending")

    entry = PostingSchedule.new(now: @now).channel_queues.sole.entries.sole
    assert_equal @now, entry.earliest_at
  end

  test "a disabled channel gets no estimate" do
    @channel.update!(enabled: false)
    TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "pending")

    queue = PostingSchedule.new(now: @now).channel_queues.sole
    assert queue.paused?
    assert_nil queue.entries.sole.earliest_at
  end

  test "filters by channel and ignores delivered posts" do
    other = create_channel(name: "Other", channel_id: "@other")
    TelegramPost.create!(translation: create_translation, telegram_channel: @channel, status: "pending")
    TelegramPost.create!(translation: create_translation, telegram_channel: other, status: "pending")
    TelegramPost.create!(translation: create_translation, telegram_channel: other, status: "posted", posted_at: @now)

    queues = PostingSchedule.new(channel_id: other.id, now: @now).channel_queues
    assert_equal [ other ], queues.map(&:channel)
    assert_equal 1, queues.sole.entries.size
  end
end
