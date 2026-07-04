class TelegramChannel < ApplicationRecord
  # `token` (the bot token) is excluded from version snapshots so it never
  # lingers in the audit trail (readable on the admin activity log page).
  has_paper_trail ignore: [ :token ]

  has_many :telegram_posts, dependent: :destroy

  validates :name, presence: true
  validates :token, presence: true
  validates :channel_id, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :autopost, -> { enabled.where(autopost: true) }
end
