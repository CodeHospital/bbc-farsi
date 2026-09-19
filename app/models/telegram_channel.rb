class TelegramChannel < ApplicationRecord
  # `token` (the bot token) is excluded from version snapshots so it never
  # lingers in the audit trail (readable on the admin activity log page).
  has_paper_trail ignore: [ :token ]

  has_many :telegram_posts, dependent: :destroy
  # Feeds pointed at this channel (Feed#autopost_telegram_channel) just stop
  # autoposting when the channel is deleted, rather than blocking deletion —
  # without :nullify, `destroy` would hit the raw DB foreign-key constraint.
  has_many :autoposting_feeds, class_name: "Feed", foreign_key: :autopost_telegram_channel_id,
                                inverse_of: :autopost_telegram_channel, dependent: :nullify

  validates :name, presence: true
  validates :token, presence: true
  validates :channel_id, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :autopost, -> { enabled.where(autopost: true) }
end
