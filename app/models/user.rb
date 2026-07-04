class User < ApplicationRecord
  has_secure_password

  has_paper_trail ignore: [ :password_digest ]

  ROLES = %w[admin editor].freeze
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\z/

  validates :username, presence: true, uniqueness: { case_sensitive: false }
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: EMAIL_FORMAT }
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: 8 }, allow_nil: true

  validate :at_least_one_active_admin_remains, on: :update

  before_validation { self.email = email.strip.downcase if email.present? }

  # Password reset link tokens. `password_salt` (from `has_secure_password`)
  # is folded into the signature, so a token is automatically invalidated the
  # moment the password is changed (including by using the token itself).
  generates_token_for :password_reset, expires_in: 20.minutes do
    password_salt&.last(10)
  end

  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }

  def admin?  = role == "admin"
  def editor? = role == "editor"

  def self.authenticate(username, password)
    user = active.find_by("LOWER(username) = ?", username.to_s.downcase)
    user if user&.authenticate(password)
  end

  private

  # Blocks the update that would take the last remaining active admin out of
  # that state (demoting them to editor, or deactivating them) — without
  # this, an admin could lock everyone (including themselves) out of the
  # infrastructure/user-management pages with no way back in.
  def at_least_one_active_admin_remains
    was_active_admin = role_was == "admin" && active_was
    return unless was_active_admin
    return if admin? && active?
    return if User.active.admins.where.not(id: id).exists?

    errors.add(:base, "Can't remove the last active admin.")
  end
end
