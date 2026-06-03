class Rewrite < ApplicationRecord
  belongs_to :article
  belongs_to :ollama_server, optional: true
  has_many :translations, dependent: :destroy

  STATUSES = %w[pending running completed error].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "completed") }
  scope :not_archived, -> { where(archived: false) }
  scope :active_version, -> { where(active: true) }
  scope :pending_translation, -> { completed.where.not(id: Translation.select(:rewrite_id)) }

  def archive! = update!(archived: true)

  def activate!
    article.rewrites.where.not(id: id).update_all(active: false)
    update!(active: true)
  end
end
