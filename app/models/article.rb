class Article < ApplicationRecord
  belongs_to :feed
  has_many :rewrites, dependent: :destroy
  has_many :translations, dependent: :destroy
  has_many :article_views, dependent: :destroy

  validates :url, presence: true, uniqueness: true
  validates :title, presence: true

  before_save :ensure_slug

  STATUSES = %w[pending rewriting rewritten translating translated posted error].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :not_archived, -> { where(archived: false) }
  scope :pending_rewrite, -> { where(status: "pending") }
  scope :rewritten, -> { where(status: "rewritten") }

  IGNORE_TITLE_PREFIXES = %w[Watch: Assignment: Speak: Podcast: Newsletter: Trending:].freeze
  IGNORE_URL_KEYWORDS   = %w[iplayer programmes sounds].freeze

  def self.ignorable?(title, url)
    IGNORE_TITLE_PREFIXES.any? { |p| title.to_s.include?(p) } ||
      IGNORE_URL_KEYWORDS.any? { |k| url.to_s.include?(k) }
  end

  def archive! = update!(archived: true)
  def unarchive! = update!(archived: false)

  # A pass-through "rewrite" holding the article's own text, used to translate
  # the original article directly without first running an AI rewrite.
  # Satisfies the NOT NULL rewrite_id on translations without a schema change.
  ORIGINAL_REWRITE_MODEL = "original".freeze

  def original_rewrite!
    rewrites.find_or_create_by!(llm_model: ORIGINAL_REWRITE_MODEL) do |original|
      original.content = description.presence || title
      original.status  = "completed"
    end
  end

  def latest_rewrite
    rewrites.order(created_at: :desc).first
  end

  def latest_translation
    translations.order(created_at: :desc).first
  end

  private

  # Populate the slug column once from the English article title.
  # Appends "-2", "-3", … to resolve collisions. Skips when the slug column
  # has not yet been added via migration.
  def ensure_slug
    return if slug.present?
    return if (base = compute_slug(title)).blank?

    candidate = base
    while Article.where(slug: candidate).where.not(id: id).exists?
      counter  = rand(10**16)
      candidate = "#{base}-#{counter}"
    end
    self[:slug] = candidate
  end

  def compute_slug(text)
    text.to_s.strip
      .gsub(/[[:space:]]+/, "-")
      .gsub(/[^[[:word:]]\-]/, "")
      .gsub(/-+/, "-")
      .gsub(/\A-+|-+\z/, "")
      .presence
  end
end
