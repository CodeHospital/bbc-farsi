class Article < ApplicationRecord
  belongs_to :feed
  has_many :rewrites, dependent: :destroy
  has_many :translations, dependent: :destroy

  validates :url, presence: true, uniqueness: true
  validates :title, presence: true

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
end
