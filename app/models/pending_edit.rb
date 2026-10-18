# An edit to a Translation or Rewrite proposed by an editor whose account is
# flagged `requires_edit_approval`. The change is not applied until a
# reviewer (an admin, or an editor without that flag) approves it.
#
# `proposed_changes` holds only the attributes the author actually changed
# (attribute name => new value). `base_values` snapshots those same
# attributes as they were when the author submitted, so the review page can
# warn when the live record has since changed underneath the proposal.
class PendingEdit < ApplicationRecord
  has_paper_trail

  STATUSES = %w[pending approved rejected].freeze

  # Which attributes of each editable model go through the approval flow —
  # mirrors the strong params of the corresponding admin controller.
  EDITABLE_ATTRIBUTES = {
    "Translation" => %w[translated_title translated_body],
    "Rewrite"     => %w[content]
  }.freeze

  class NotPending < StandardError; end

  belongs_to :editable, polymorphic: true
  belongs_to :author,   class_name: "User"
  belongs_to :reviewer, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :editable_type, inclusion: { in: EDITABLE_ATTRIBUTES.keys }
  validate :proposes_at_least_one_change

  scope :pending,  -> { where(status: "pending") }
  scope :reviewed, -> { where.not(status: "pending") }

  # Records (or refreshes) `author`'s proposal for `editable`. An author has
  # at most one pending edit per record: resubmitting updates it in place
  # rather than piling up near-duplicates for the reviewer. Returns the
  # (possibly unsaved, invalid) PendingEdit so the caller can show errors.
  def self.submit(editable, author:, attributes:)
    allowed_attribute_names = EDITABLE_ATTRIBUTES.fetch(editable.class.name)
    submitted_values        = attributes.to_h.stringify_keys.slice(*allowed_attribute_names)
    changed_values          = submitted_values.reject { |name, value| editable.public_send(name).to_s == value.to_s }

    pending_edit = pending.find_or_initialize_by(editable:, author:)
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

      PaperTrail.request(whodunnit: author_id.to_s) do
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

  def proposes_at_least_one_change
    errors.add(:base, "No changes to submit — the text is identical to the current version.") if proposed_changes.blank?
  end
end
