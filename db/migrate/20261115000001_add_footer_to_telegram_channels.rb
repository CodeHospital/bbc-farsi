# Per-channel footer appended after the article link of every post.
#
# Backfilled with what each provider used to hard-code, so existing posts look
# the same: Telegram always ended with "follow <channel> for more"; Bale and
# custom providers only did so for a public @username; the social platforms had
# no footer. A blank footer means "no footer".
class AddFooterToTelegramChannels < ActiveRecord::Migration[8.0]
  def up
    add_column :telegram_channels, :footer, :text

    execute <<~SQL
      UPDATE telegram_channels
      SET footer = 'follow ' || channel_id || ' for more'
      WHERE provider = 'telegram'
         OR (provider IN ('bale', 'custom') AND channel_id LIKE '@%')
    SQL
  end

  def down
    remove_column :telegram_channels, :footer
  end
end
