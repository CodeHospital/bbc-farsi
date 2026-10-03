# Join row: Feed `feed` autoposts its completed translations to `telegram_channel`
# (a channel on any Telegram-compatible provider). See Feed#autopost_channels.
class FeedAutopostChannel < ApplicationRecord
  belongs_to :feed
  belongs_to :telegram_channel

  validates :telegram_channel_id, uniqueness: { scope: :feed_id }
end
