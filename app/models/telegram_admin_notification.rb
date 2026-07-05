# One row per admin-bot message sent for a translation (see TelegramAdminNotifier).
# Tracks the Telegram chat/message id so a later button tap can edit the same
# message in place, plus a lightweight audit trail of who actioned it and how.
class TelegramAdminNotification < ApplicationRecord
  belongs_to :translation

  STATUSES = %w[sent actioned].freeze
  validates :chat_id, presence: true
  validates :message_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :awaiting_action, -> { where(status: "sent") }
end
