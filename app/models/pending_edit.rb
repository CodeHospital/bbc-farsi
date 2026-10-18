# An edit to a Translation or Rewrite proposed by an editor whose account is
# flagged `requires_edit_approval`. The change is not applied until a
# reviewer (an admin, or an editor without that flag) approves it.
#
# `proposed_changes` holds only the attributes the author actually changed
# (attribute name => new value). `base_values` snapshots those same
# attributes as they were when the author submitted, so the review page can
# warn when the live record has since changed underneath the proposal.
#
# The author is normally a restricted editor (`author`). Edits made through an
# EditLink "magic link" have no user: `author` is nil and the visitor's
# self-declared name/email/phone are kept in the guest_* columns.
class PendingEdit < ApplicationRecord
  has_paper_trail

  STATUSES = %w[pending approved rejected].freeze

  # Which attributes of each editable model go through the approval flow —
  # mirrors the strong params of the corresponding admin controller.
  EDITABLE_ATTRIBUTES = {
    "Translation" => %w[translated_title translated_body],
    "Rewrite"     => %w[content]
  }.freeze

  GUEST_PHONE_FORMAT = /\A\+?[\d\s().\-\/]{5,30}\z/

  class NotPending < StandardError; end

  belongs_to :editable, polymorphic: true
  belongs_to :author,    class_name: "User", optional: true
  belongs_to :reviewer,  class_name: "User", optional: true
  belongs_to :edit_link, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :editable_type, inclusion: { in: EDITABLE_ATTRIBUTES.keys }
  validates :guest_name, presence: true, length: { maximum: 120 }, if: :guest?
  validates :guest_email, presence: true, format: { with: User::EMAIL_FORMAT }, length: { maximum: 254 }, if: :guest?
  validates :guest_phone, presence: true, format: { with: GUEST_PHONE_FORMAT, message: "doesn't look like a phone number" }, if: :guest?
  validate :has_an_author_or_guest_identity
  validate :proposes_at_least_one_change

  scope :pending,  -> { where(status: "pending") }
  scope :reviewed, -> { where.not(status: "pending") }

  # Records (or refreshes) a proposal for `editable`, either by an `author`
  # (a User) or by a guest arriving through an `edit_link` (identified by the
  # guest_* details). Each author — or guest email per link — has at most one
  # pending edit per record: resubmitting updates it in place rather than
  # piling up near-duplicates for the reviewer. Returns the (possibly unsaved,
  # invalid) PendingEdit so the caller can show errors.
  def self.submit(editable, attributes:, author: nil, edit_link: nil, guest_name: nil, guest_email: nil, guest_phone: nil, guest_ip: nil)
    allowed_attribute_names = EDITABLE_ATTRIBUTES.fetch(editable.class.name)
    submitted_values        = attributes.to_h.stringify_keys.slice(*allowed_attribute_names)
    changed_values          = submitted_values.reject { |name, value| editable.public_send(name).to_s == value.to_s }

    if author
      pending_edit = pending.find_or_initialize_by(editable:, author:)
    else
      pending_edit = pending.find_or_initialize_by(editable:, author: nil, edit_link:, guest_email: guest_email.to_s.strip.downcase)
      pending_edit.assign_attributes(guest_name: guest_name.to_s.strip, guest_phone: guest_phone.to_s.strip, guest_ip: guest_ip.to_s.strip.presence)
    end
    previous_base_values = pending_edit.base_values || {}
    pending_edit.proposed_changes = changed_values
    # Keep the original snapshot for attributes the author was already
    # proposing, so a resubmission can't mask an intervening live change.
    pending_edit.base_values = changed_values.keys.index_with do |name|
      previous_base_values.key?(name) ? previous_base_values[name] : editable.public_send(name)
    end
    pending_edit.save
    pending_edit
  end

  def guest? = author_id.nil?

  # Resolves guest_ip to a country/city (cached lookups; never raises). Called
  # after a guest submission is saved so a slow lookup can't lose the edit.
  def record_location!
    return if guest_ip.blank?

    country_name, city_name = ArticleView.location_for_ip(guest_ip)
    update_columns(guest_country_name: country_name, guest_city_name: city_name)
  end

  # "Aachen, Germany", "Germany", or nil when the IP couldn't be located.
  def guest_location = [ guest_city_name, guest_country_name ].compact_blank.join(", ").presence

  # Display name for lists and timelines.
  def author_name = guest? ? "#{guest_name.presence || 'Guest'} (guest)" : author.username

  # PaperTrail `whodunnit` for the version written when this edit is approved
  # (see VersionsHelper#version_actor, which understands the "guest:" form).
  def whodunnit_value = guest? ? "guest:#{guest_name}" : author_id.to_s

  def pending?  = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"

  # Applies the proposal to the live record. The resulting PaperTrail version
  # is attributed to the author (it's their text); the reviewer is recorded on
  # this row.
  def approve!(reviewer:, note: nil)
    transaction do
      lock!
      raise NotPending, "This edit has already been #{status}." unless pending?

      PaperTrail.request(whodunnit: whodunnit_value) do
        editable.update!(proposed_changes)
      end
      update!(status: "approved", reviewer:, review_note: note.presence, reviewed_at: Time.current)
    end
  end

  def reject!(reviewer:, note: nil)
    transaction do
      lock!
      raise NotPending, "This edit has already been #{status}." unless pending?

      update!(status: "rejected", reviewer:, review_note: note.presence, reviewed_at: Time.current)
    end
  end

  # Attribute names whose live value no longer matches what the author saw
  # when they submitted — approving would overwrite someone else's change.
  def conflicting_attribute_names
    return [] unless pending? && editable

    base_values.keys.reject { |name| editable.public_send(name).to_s == base_values[name].to_s }
  end

  # The value shown on the "before" side of the review diff: the live value
  # while pending (what approving would replace), the snapshot once reviewed.
  def current_value_for(attribute_name)
    pending? && editable ? editable.public_send(attribute_name) : base_values[attribute_name]
  end

  private

  def has_an_author_or_guest_identity
    errors.add(:base, "An edit needs an author or guest details.") if guest? && edit_link.nil?
  end

  def proposes_at_least_one_change
    errors.add(:base, "No changes to submit — the text is identical to the current version.") if proposed_changes.blank?
  end
end
