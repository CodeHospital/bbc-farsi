class Admin::BaseController < ApplicationController
  # Public portal readers skew toward older Android WebView/Chrome builds and
  # must not get a bare 406 — restrict the modern-browser requirement to admin.
  allow_browser versions: :modern
  protect_from_forgery with: :null_session

  before_action :require_login

  private

  def require_login
    redirect_to admin_login_path, alert: "Please log in." unless current_user
  end

  # Restricts an action to admins; editors get redirected with an alert.
  # Add as a `before_action :require_admin!` in controllers that manage
  # infrastructure/configuration rather than editorial content.
  def require_admin!
    redirect_to admin_root_path, alert: "You don't have permission to do that." unless current_user&.admin?
  end

  # Restricts an action to users allowed to approve/reject queued edits
  # (admins and editors without `requires_edit_approval`).
  def require_edit_reviewer!
    redirect_to admin_pending_edits_path, alert: "Only admins and approved editors can review edits." unless current_user&.can_review_edits?
  end

  # For a restricted editor, pre-fills the edit form with their own
  # still-pending proposal (so reopening the form doesn't lose it) and
  # returns that PendingEdit; nil for everyone else.
  def apply_own_pending_edit(editable)
    return unless current_user.edits_need_approval?

    own_pending_edit = editable.pending_edits.pending.find_by(author: current_user)
    editable.assign_attributes(own_pending_edit.proposed_changes) if own_pending_edit
    own_pending_edit
  end

  # Queues a restricted editor's change instead of saving it. Returns the
  # PendingEdit; on failure its errors are set and the submitted values are
  # assigned to `editable` (unsaved) so the form can be re-rendered as typed.
  def submit_edit_for_approval(editable, submitted_attributes)
    pending_edit = PendingEdit.submit(editable, author: current_user, attributes: submitted_attributes)
    editable.assign_attributes(submitted_attributes) if pending_edit.errors.any?
    pending_edit
  end

  def pagy_defaults
    @pagy_defaults ||= { limit: 30 }
  end
end
