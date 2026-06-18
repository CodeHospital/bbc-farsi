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

  # Friendly, SEO-oriented URL param for the public news routes: "<id>-<slug>".
  # The id stays a prefix so `params[:id].to_i` recovers the primary key on any
  # database (no slug column — derived on the fly from the Persian title).
  # NB: `to_param` is intentionally NOT overridden, so admin routes keep using
  # the numeric id (a Persian slug would break `find` on PostgreSQL).
  def seo_param
    [ id, slug ].compact_blank.join("-")
  end

  # A URL slug from the Persian title: word characters (Persian letters/digits
  # included) kept, everything else collapsed to single hyphens.
  def slug
    translated_title.to_s.strip
      .gsub(/[[:space:]]+/, "-")
      .gsub(/[^[[:word:]]\-]/, "")
      .gsub(/-+/, "-")
      .gsub(/\A-+|-+\z/, "")
      .presence
  end

  def activate!
    article.translations.where.not(id: id).update_all(active: false)
    update!(active: true)
  end
end
