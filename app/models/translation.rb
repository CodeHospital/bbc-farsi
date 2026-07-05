class Translation < ApplicationRecord
  has_paper_trail

  belongs_to :article
  belongs_to :rewrite
  belongs_to :ollama_server, optional: true
  has_many :telegram_posts, dependent: :destroy
  has_many :telegram_admin_notifications, dependent: :destroy
  has_many :tasks, as: :target

  STATUSES = %w[pending running completed error].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "completed") }
  scope :not_archived, -> { where(archived: false) }
  scope :active_version, -> { where(active: true) }
  scope :needs_manual_edit, -> { where(needs_manual_edit: true) }
  scope :unposted_for, ->(channel) {
    completed.where.not(id: TelegramPost.where(telegram_channel: channel).select(:translation_id))
  }

  before_save :ensure_slug

  def archive!   = update!(archived: true)
  def unarchive! = update!(archived: false)

  def mark_for_manual_edit! = update!(needs_manual_edit: true)
  def clear_manual_edit!    = update!(needs_manual_edit: false)

  # Public URL param for news routes. Returns the stored slug column when
  # available (after the slug migration); falls back to "<id>-<computed>" so
  # the site keeps working before the migration is applied.
  # NB: `to_param` is intentionally NOT overridden — admin routes keep the
  # numeric id so `find` works on PostgreSQL without a slug column.
  def seo_param
    return slug if self.class.column_names.include?("slug") && slug.present?
    [ id, computed_slug ].compact_blank.join("-")
  end

  # Derive a URL-safe slug from the Persian title (word chars kept, everything
  # else collapsed to hyphens). Used internally to populate the slug column.
  def computed_slug
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

  # The Task whose LLM requests produced this translation — used to show
  # which prompt version(s) created it (see PromptVersionUsage). Excludes
  # read-only "tag" tasks, which annotate an already-completed translation
  # rather than generating one.
  def generating_task = tasks.where(kind: %w[translate refine]).order(:created_at).last

  private

  # Populate the slug column once (on first save with a non-blank title).
  # Appends "-2", "-3", … to resolve uniqueness collisions. Skips gracefully
  # when the slug column has not yet been added via migration.
  def ensure_slug
    return if slug.present?
    return if (base = computed_slug).blank?

    candidate = base
    while Translation.where(slug: candidate).where.not(id: id).exists?
      counter  = rand(10**16) # add some jitter to reduce collisions when backfilling many records
      candidate = "#{base}-#{counter}"
    end
    self[:slug] = candidate
  end
end
