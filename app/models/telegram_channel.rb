class TelegramChannel < ApplicationRecord
  has_many :telegram_posts, dependent: :destroy

  validates :name, presence: true
  validates :token, presence: true
  validates :channel_id, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :autopost, -> { enabled.where(autopost: true) }
end
