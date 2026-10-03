require "test_helper"
require Rails.root.join("db/migrate/20261003000002_create_feed_autopost_channels")

# Exercises the migration's code against the throwaway test database only —
# rolls it down to the old single-column schema and back up inside the test
# transaction (SQLite DDL is transactional), checking the data carries over.
class CreateFeedAutopostChannelsTest < ActiveSupport::TestCase
  setup do
    @connection = ActiveRecord::Base.connection
  end

  teardown do
    Feed.reset_column_information
    FeedAutopostChannel.reset_column_information
  end

  test "carries existing per-feed autopost channels into the join table, both ways" do
    first_channel  = create_channel(name: "First")
    second_channel = create_channel(name: "Second", channel_id: "@second")
    autoposting_feed     = create_feed(url: "https://feeds.bbci.co.uk/news/migration-a.rss", autopost_target_channels: [ second_channel, first_channel ])
    not_autoposting_feed = create_feed(url: "https://feeds.bbci.co.uk/news/migration-b.rss")

    run_migration(:down)
    assert @connection.column_exists?(:feeds, :autopost_telegram_channel_id)
    assert_not @connection.table_exists?(:feed_autopost_channels)
    autopost_column_by_feed_id = @connection.select_rows("SELECT id, autopost_telegram_channel_id FROM feeds").to_h
    assert_equal [ first_channel.id, second_channel.id ].min, autopost_column_by_feed_id[autoposting_feed.id]
    assert_nil autopost_column_by_feed_id[not_autoposting_feed.id]

    run_migration(:up)
    assert_not @connection.column_exists?(:feeds, :autopost_telegram_channel_id)
    links = @connection.select_rows("SELECT feed_id, telegram_channel_id FROM feed_autopost_channels")
    assert_equal [ [ autoposting_feed.id, [ first_channel.id, second_channel.id ].min ] ], links
  end

  private

  def run_migration(direction)
    ActiveRecord::Migration.suppress_messages { CreateFeedAutopostChannels.new.migrate(direction) }
    Feed.reset_column_information
  end
end
