class TelegramPost < ApplicationRecord
  belongs_to :translation
  belongs_to :telegram_channel

  STATUSES = %w[pending posted error].freeze
  validates :status, inclusion: { in: STATUSES }
  # Backed by a DB unique index (M-4 from plan2.md) so concurrent posters
  # (autopost sweep, task chain, admin bot) can't create duplicate rows for
  # the same translation+channel — see Publisher.
  validates :translation_id, uniqueness: { scope: :telegram_channel_id }

  scope :posted, -> { where(status: "posted") }
end
