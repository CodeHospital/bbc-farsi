# One chronological timeline of everything done to an article's rewrites and
# translations: saved changes (PaperTrail versions) and edit-approval
# proposals (PendingEdit), newest first.
#
# Saved changes made with no signed-in user (AI worker, scheduler) are
# "system" entries and are left out unless `include_system` is set. A
# version created by approving a PendingEdit is folded into that proposal's
# entry instead of being listed twice.
class ArticleEditHistory
  Entry = Struct.new(
    :occurred_at, :kind, :record_type, :record_id, :actor_name, :event, :text_changes,
    :other_changed_attributes, :system, :status, :reviewer_name, :review_note, :pending_edit_id,
    keyword_init: true
  )

  # Text attributes shown as before/after diffs (versions + proposals).
  TEXT_ATTRIBUTES = PendingEdit::EDITABLE_ATTRIBUTES.values.flatten.push("rewritten_title").freeze
  # Bookkeeping columns not worth listing as "also changed".
  IGNORED_ATTRIBUTES = %w[updated_at created_at].freeze
  # Tolerance when matching an approval's version to its PendingEdit
  # (the version is written just before `reviewed_at`).
  APPROVAL_MATCH_WINDOW = 10.seconds

  def initialize(article, include_system: false)
    @article        = article
    @include_system = include_system
  end

  def entries
    pending_edits = PendingEdit.where(editable: records).includes(:author, :reviewer).to_a
    version_entries  = versions.filter_map { |version| version_entry(version, pending_edits) }
    proposal_entries = pending_edits.map { |pending_edit| proposal_entry(pending_edit) }

    (version_entries + proposal_entries).sort_by(&:occurred_at).reverse
  end

  # Number of system (non-human) saved changes hidden from the default view.
  def hidden_system_count
    @include_system ? 0 : versions.count { |version| version.whodunnit.blank? }
  end

  private

  def rewrites     = @rewrites     ||= @article.rewrites.to_a
  def translations = @translations ||= @article.translations.to_a
  def records      = rewrites + translations

  def versions
    @versions ||= PaperTrail::Version
      .where(item_type: "Rewrite", item_id: rewrites.map(&:id))
      .or(PaperTrail::Version.where(item_type: "Translation", item_id: translations.map(&:id)))
      .order(:created_at).to_a
  end

  def actor_names_by_id
    @actor_names_by_id ||= User.where(id: versions.filter_map { |version| version.whodunnit.presence }.grep_v(/\Aguest:/)).pluck(:id, :username).to_h { |id, name| [ id.to_s, name ] }
  end

  def version_entry(version, pending_edits)
    system_change = version.whodunnit.blank?
    return if system_change && !@include_system
    return if approval_version?(version, pending_edits)

    changes         = version.object_changes ? version.changeset : {}
    visible_changes = changes.except(*IGNORED_ATTRIBUTES)
    return if version.event == "update" && visible_changes.empty?

    Entry.new(
      occurred_at: version.created_at, kind: :change, record_type: version.item_type, record_id: version.item_id,
      actor_name: system_change ? "AI worker / system" : version_actor_name(version),
      event: version.event, system: system_change,
      text_changes: visible_changes.slice(*TEXT_ATTRIBUTES),
      other_changed_attributes: visible_changes.keys - TEXT_ATTRIBUTES
    )
  end

  def version_actor_name(version)
    return "#{version.whodunnit.delete_prefix('guest:')} (guest)" if version.whodunnit.start_with?("guest:")

    actor_names_by_id.fetch(version.whodunnit, "Deleted user ##{version.whodunnit}")
  end

  def approval_version?(version, pending_edits)
    pending_edits.any? do |pending_edit|
      pending_edit.approved? && pending_edit.reviewed_at &&
        pending_edit.editable_type == version.item_type && pending_edit.editable_id == version.item_id &&
        version.whodunnit == pending_edit.whodunnit_value &&
        version.created_at.between?(pending_edit.reviewed_at - APPROVAL_MATCH_WINDOW, pending_edit.reviewed_at + 1.second)
    end
  end

  def proposal_entry(pending_edit)
    text_changes = pending_edit.proposed_changes.to_h do |attribute_name, proposed_value|
      [ attribute_name, [ pending_edit.base_values[attribute_name], proposed_value ] ]
    end

    Entry.new(
      occurred_at: pending_edit.reviewed_at || pending_edit.created_at, kind: :proposal,
      record_type: pending_edit.editable_type, record_id: pending_edit.editable_id,
      actor_name: pending_edit.author_name, event: "proposal", system: false,
      text_changes:, other_changed_attributes: [], status: pending_edit.status,
      reviewer_name: pending_edit.reviewer&.username, review_note: pending_edit.review_note,
      pending_edit_id: pending_edit.id
    )
  end
end
