class Translation < ApplicationRecord
  belongs_to :article
  belongs_to :rewrite
  belongs_to :ollama_server, optional: true
  has_many :telegram_posts, dependent: :destroy

  STATUSES = %w[pending running completed error].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "completed") }
  scope :not_archived, -> { where(archived: false) }
  scope :active_version, -> { where(active: true) }
  scope :unposted_for, ->(channel) {
    completed.where.not(id: TelegramPost.where(telegram_channel: channel).select(:translation_id))
  }

  def archive! = update!(archived: true)

  def activate!
    article.translations.where.not(id: id).update_all(active: false)
    update!(active: true)
  end
end
