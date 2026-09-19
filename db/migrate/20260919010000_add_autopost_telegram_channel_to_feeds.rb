class AddAutopostTelegramChannelToFeeds < ActiveRecord::Migration[8.0]
  def change
    # nil = don't autopost this feed's articles at all (the default).
    add_reference :feeds, :autopost_telegram_channel, foreign_key: { to_table: :telegram_channels }
  end
end
