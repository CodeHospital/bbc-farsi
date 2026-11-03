class TelegramPost < ApplicationRecord
  belongs_to :translation
  belongs_to :telegram_channel

  # "sending" is a brief transient state Publisher holds a post in while it
  # atomically claims it for delivery, so two concurrent delivery sweeps
  # (e.g. multiple Puma workers) can't both send the same queued post.
  #
  # "cancelled" is an admin withdrawing a queued post. The row is kept (rather
  # than deleted) so Autoposter's `unposted_for` doesn't just queue it again;
  # a manual "post now" reuses the row via Publisher#claim_post!.
  STATUSES = %w[pending sending posted error cancelled].freeze
  validates :status, inclusion: { in: STATUSES }
  # Backed by a DB unique index (M-4 from plan2.md) so concurrent posters
  # (autopost sweep, task chain, admin bot) can't create duplicate rows for
  # the same translation+channel — see Publisher.
  validates :translation_id, uniqueness: { scope: :telegram_channel_id }

  scope :posted, -> { where(status: "posted") }
end
