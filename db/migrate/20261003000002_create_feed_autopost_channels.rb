class CreateFeedAutopostChannels < ActiveRecord::Migration[8.0]
  # Replaces the single feeds.autopost_telegram_channel_id slot with a join
  # table, so a feed can autopost to any set of channels across providers
  # (Telegram, Bale, custom Telegram-compatible APIs) instead of at most one
  # Telegram channel. Existing assignments are carried over.
  def up
    create_table :feed_autopost_channels do |t|
      t.references :feed, null: false, foreign_key: true
      t.references :telegram_channel, null: false, foreign_key: true
      t.timestamps
    end
    add_index :feed_autopost_channels, [ :feed_id, :telegram_channel_id ], unique: true,
      name: "index_feed_autopost_channels_on_feed_and_channel"

    execute <<~SQL
      INSERT INTO feed_autopost_channels (feed_id, telegram_channel_id, created_at, updated_at)
      SELECT id, autopost_telegram_channel_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM feeds WHERE autopost_telegram_channel_id IS NOT NULL
    SQL

    remove_reference :feeds, :autopost_telegram_channel, foreign_key: { to_table: :telegram_channels }, index: true
  end

  # Best-effort: the old schema holds only one channel per feed, so a feed
  # autoposting to several channels keeps just its lowest-id one.
  def down
    add_reference :feeds, :autopost_telegram_channel, foreign_key: { to_table: :telegram_channels }

    execute <<~SQL
      UPDATE feeds SET autopost_telegram_channel_id = (
        SELECT MIN(telegram_channel_id) FROM feed_autopost_channels WHERE feed_autopost_channels.feed_id = feeds.id
      )
    SQL

    drop_table :feed_autopost_channels
  end
end
