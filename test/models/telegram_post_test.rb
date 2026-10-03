require "test_helper"

class TelegramPostTest < ActiveSupport::TestCase
  setup do
    @channel     = create_channel
    @translation = create_translation
  end

  test "model validation rejects a second post for the same translation and channel" do
    TelegramPost.create!(translation: @translation, telegram_channel: @channel, status: "pending")
    assert_not TelegramPost.new(translation: @translation, telegram_channel: @channel, status: "pending").valid?
  end

  # The validation alone can't stop two concurrent callers (both check, both
  # pass, both insert). Publisher relies on the DB unique index
  # index_telegram_posts_on_translation_and_channel raising RecordNotUnique for
  # the loser — this fails if db/schema.rb ever drifts from that migration again.
  test "the database itself rejects a duplicate translation+channel row that skipped validation" do
    TelegramPost.create!(translation: @translation, telegram_channel: @channel, status: "pending")
    duplicate_post = TelegramPost.new(translation: @translation, telegram_channel: @channel, status: "pending")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate_post.save!(validate: false) }
  end

  test "the same translation can still be posted to a different channel" do
    other_channel = create_channel(name: "Other", channel_id: "@other")
    TelegramPost.create!(translation: @translation, telegram_channel: @channel, status: "pending")

    assert TelegramPost.create!(translation: @translation, telegram_channel: other_channel, status: "pending").persisted?
  end
end
