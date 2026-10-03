require "test_helper"
require Rails.root.join("db/migrate/20261003000003_ensure_unique_index_on_telegram_posts")

# Exercises the migration's code against the throwaway test database only —
# SQLite DDL is transactional, so the dropped/re-added index is rolled back
# with the rest of the test transaction.
class EnsureUniqueIndexOnTelegramPostsTest < ActiveSupport::TestCase
  INDEX_NAME = EnsureUniqueIndexOnTelegramPosts::INDEX_NAME

  setup do
    @connection  = ActiveRecord::Base.connection
    @channel     = create_channel
    @translation = create_translation
  end

  test "is a no-op when the index already exists" do
    post = TelegramPost.create!(translation: @translation, telegram_channel: @channel, status: "posted")

    run_migration

    assert index_present?
    assert TelegramPost.exists?(post.id)
  end

  test "collapses duplicates (keeping the posted row) and adds the missing index" do
    @connection.remove_index :telegram_posts, name: INDEX_NAME
    errored_post = insert_post(status: "error")
    posted_post  = insert_post(status: "posted")
    pending_post = insert_post(status: "pending")
    other_channel_post = TelegramPost.create!(translation: @translation, telegram_channel: create_channel(name: "Other", channel_id: "@other"),
                                              status: "pending")

    run_migration

    assert index_present?
    assert TelegramPost.exists?(posted_post.id)
    assert_not TelegramPost.exists?(errored_post.id)
    assert_not TelegramPost.exists?(pending_post.id)
    assert TelegramPost.exists?(other_channel_post.id)
  end

  test "keeps the oldest row when none of the duplicates was posted" do
    @connection.remove_index :telegram_posts, name: INDEX_NAME
    oldest_post = insert_post(status: "error")
    newer_post  = insert_post(status: "pending")

    run_migration

    assert TelegramPost.exists?(oldest_post.id)
    assert_not TelegramPost.exists?(newer_post.id)
  end

  private

  def insert_post(status:)
    TelegramPost.new(translation: @translation, telegram_channel: @channel, status:).tap { |post| post.save!(validate: false) }
  end

  def index_present?
    @connection.index_exists?(:telegram_posts, [ :translation_id, :telegram_channel_id ], name: INDEX_NAME, unique: true)
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { EnsureUniqueIndexOnTelegramPosts.new.migrate(:up) }
  end
end
