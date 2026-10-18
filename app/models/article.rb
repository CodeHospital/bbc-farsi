class Article < ApplicationRecord
  has_paper_trail

  belongs_to :feed
  has_many :rewrites, dependent: :destroy
  has_many :translations, dependent: :destroy
  has_many :article_views, dependent: :destroy

  validates :url, presence: true, uniqueness: true
  validates :title, presence: true

  before_save :ensure_slug

  STATUSES = %w[pending rewriting rewritten translating translated posted error].freeze
  validates :status, inclusion: { in: STATUSES }

  # AI analysis of the original article (see ArticleAnalyzer); admins can
  # edit these. Each split must add up to 100 once any part of it is set.
  BIAS_PERCENT_ATTRIBUTES   = %i[bias_left_percent bias_center_percent bias_right_percent].freeze
  NATURE_PERCENT_ATTRIBUTES = %i[factual_percent speculative_percent].freeze
  ANALYSIS_PERCENT_ATTRIBUTES = (BIAS_PERCENT_ATTRIBUTES + NATURE_PERCENT_ATTRIBUTES).freeze
  ANALYSIS_STATUSES = %w[pending completed failed].freeze

  validates(*ANALYSIS_PERCENT_ATTRIBUTES,
            numericality: { only_integer: true, in: 0..100 }, allow_nil: true)
  validates :analysis_status, inclusion: { in: ANALYSIS_STATUSES }, allow_nil: true
  validate :analysis_splits_sum_to_hundred

  scope :not_archived, -> { where(archived: false) }
  scope :pending_rewrite, -> { where(status: "pending") }
  scope :rewritten, -> { where(status: "rewritten") }

  def self.ignorable?(title, url)
    ignore_reason(title, url).present?
  end

  # nil when the entry should be ingested; otherwise a human-readable reason,
  # used to explain skipped entries in a single-feed fetch report. The phrases
  # are admin-editable (see SkipPhrase); matching is case-insensitive.
  def self.ignore_reason(title, url)
    phrases = SkipPhrase.enabled_by_field

    matched_title_phrase = phrases["title"].find { |phrase| title.to_s.downcase.include?(phrase.downcase) }
    return "title contains skip phrase #{matched_title_phrase.inspect}" if matched_title_phrase

    matched_url_phrase = phrases["url"].find { |phrase| url.to_s.downcase.include?(phrase.downcase) }
    return "URL contains skip phrase #{matched_url_phrase.inspect}" if matched_url_phrase

    nil
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

  def analyzed?
    ANALYSIS_PERCENT_ATTRIBUTES.all? { |attribute| self[attribute].present? }
  end

  private

  def analysis_splits_sum_to_hundred
    { "Political leaning (left + center + right)" => BIAS_PERCENT_ATTRIBUTES,
      "Factual + speculative"                    => NATURE_PERCENT_ATTRIBUTES }.each do |label, attributes|
      values = attributes.map { |attribute| self[attribute] }
      next if values.all?(&:nil?)

      if values.any?(&:nil?)
        errors.add(:base, "#{label} must all be filled in")
      elsif values.sum != 100
        errors.add(:base, "#{label} must add up to 100 (currently #{values.sum})")
      end
    end
  end

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
