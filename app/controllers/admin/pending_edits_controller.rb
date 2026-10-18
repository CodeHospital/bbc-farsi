# Review queue for edits made by editors flagged `requires_edit_approval`.
# Reviewers (admins + unrestricted editors) see everyone's edits and can
# approve/reject them; restricted editors see only their own and can
# withdraw them while still pending.
class Admin::PendingEditsController < Admin::BaseController
  include Pagy::Method

  before_action :set_pending_edit, only: %i[show approve reject destroy]
  before_action :require_edit_reviewer!, only: %i[approve reject]

  def index
    base = visible_pending_edits
    @status_counts = base.group(:status).count
    @status        = PendingEdit::STATUSES.include?(params[:status]) ? params[:status] : "pending"

    pending_edits = base.where(status: @status).includes(:author, :reviewer, :editable)
    pending_edits = @status == "pending" ? pending_edits.order(created_at: :asc) : pending_edits.order(reviewed_at: :desc)
    @pagy, @pending_edits = pagy(pending_edits)
  end

  def show
    @other_pending_edits = PendingEdit.pending.where(editable: @pending_edit.editable)
                                      .where.not(id: @pending_edit.id).includes(:author)
  end

  def approve
    @pending_edit.approve!(reviewer: current_user, note: params[:review_note])
    redirect_to next_review_path, notice: "Edit approved and published."
  rescue PendingEdit::NotPending, ActiveRecord::RecordInvalid => error
    redirect_to admin_pending_edit_path(@pending_edit), alert: "Not approved: #{error.message}"
  end

  def reject
    @pending_edit.reject!(reviewer: current_user, note: params[:review_note])
    redirect_to next_review_path, notice: "Edit rejected."
  rescue PendingEdit::NotPending => error
    redirect_to admin_pending_edit_path(@pending_edit), alert: error.message
  end

  # Authors withdraw their own still-pending proposal.
  def destroy
    unless @pending_edit.pending? && @pending_edit.author_id == current_user.id
      return redirect_to admin_pending_edit_path(@pending_edit), alert: "Only the author can withdraw a pending edit."
    end

    @pending_edit.destroy!
    redirect_to admin_pending_edits_path, notice: "Edit withdrawn."
  end

  private

  def visible_pending_edits
    current_user.can_review_edits? ? PendingEdit.all : PendingEdit.where(author: current_user)
  end

  def set_pending_edit = @pending_edit = visible_pending_edits.find(params[:id])

  # After a decision, jump straight to the oldest remaining pending edit so a
  # reviewer can work through the queue; back to the list when it's empty.
  def next_review_path
    next_pending_edit = PendingEdit.pending.order(:created_at).first
    next_pending_edit ? admin_pending_edit_path(next_pending_edit) : admin_pending_edits_path
  end
end
