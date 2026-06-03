class TelegramPost < ApplicationRecord
  belongs_to :translation
  belongs_to :telegram_channel

  STATUSES = %w[pending posted error].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :posted, -> { where(status: "posted") }
end
