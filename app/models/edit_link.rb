# A secret, expiring URL (/edit/:token) that lets someone without an account
# propose an edit to one article's published Persian translation. Their
# proposal becomes a guest PendingEdit and goes through normal approval.
class EditLink < ApplicationRecord
  has_paper_trail

  DEFAULT_LIFETIME_DAYS = 7
  LIFETIME_DAYS_OPTIONS = [ 1, 7, 30 ].freeze

  belongs_to :article
  belongs_to :created_by, class_name: "User"
  has_many :pending_edits, dependent: :nullify

  has_secure_token :token

  validates :expires_at, presence: true
  validates :note, length: { maximum: 120 }

  scope :newest_first, -> { order(created_at: :desc) }

  def self.find_usable(token)
    link = find_by(token: token.to_s)
    link if link&.usable?
  end

  def revoke! = update!(revoked_at: Time.current)

  def revoked? = revoked_at.present?
  def expired? = expires_at <= Time.current
  # A single-use link is spent by its first successful submission.
  def used_up? = single_use? && used_at.present?
  def usable?  = !revoked? && !expired? && !used_up?

  def usage_label = single_use? ? "single use" : "multiple use"

  def status
    if revoked? then "revoked"
    elsif used_up? then "used"
    elsif expired? then "expired"
    else "active"
    end
  end

  # Atomically spends a single-use link. True for the one caller that wins
  # (two simultaneous submissions can't both succeed); always true for
  # multi-use links, which are never spent.
  def claim_use!
    return true unless single_use?

    self.class.where(id:, used_at: nil).update_all(used_at: Time.current).positive?
  end

  # The translation visitors edit: the one live on the Farsi portal (newest
  # completed, non-archived translation with a title) — the same rule the
  # admin article page uses for its portal preview. nil when none is live.
  def translation
    article.translations.completed.where(archived: false)
           .where.not(translated_title: [ nil, "" ])
           .order(created_at: :desc).first
  end
end
