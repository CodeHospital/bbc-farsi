# Public (no login) page behind an EditLink magic link: /edit/:token. A visitor
# leaves their name, email and phone and proposes new title/body text for the
# article's published translation. The proposal becomes a guest PendingEdit
# and nothing goes live until a reviewer approves it.
class GuestEditsController < ApplicationController
  layout "guest_edit"

  before_action :set_edit_link, only: %i[show create]
  before_action :set_translation, only: %i[show create]
  before_action :keep_token_private

  rate_limit to: 10, within: 1.hour, only: :create, with: -> {
    redirect_to guest_edit_path(params[:token]), alert: "Too many submissions. Please try again later."
  }

  def show
    @pending_edit = nil
  end

  def create
    # Honeypot: real visitors never see or fill this field.
    return redirect_to(guest_edit_thanks_path(params[:token])) if params[:website].present?

    unless params[:consent] == "1"
      @submitted = submitted_params
      @consent_missing = true
      return render :show, status: :unprocessable_entity
    end

    # One transaction so a single-use link is only spent by a submission that
    # was actually saved (and a lost race for it saves nothing).
    link_already_spent = false
    EditLink.transaction do
      unless @edit_link.claim_use!
        link_already_spent = true
        raise ActiveRecord::Rollback
      end

      @pending_edit = PendingEdit.submit(
        @translation,
        attributes: translation_params,
        edit_link: @edit_link,
        guest_name: submitted_params[:guest_name], guest_email: submitted_params[:guest_email], guest_phone: submitted_params[:guest_phone],
        guest_ip: request.remote_ip
      )
      raise ActiveRecord::Rollback if @pending_edit.errors.any?
    end

    return render(:unavailable, status: :not_found) if link_already_spent

    if @pending_edit.errors.none?
      @pending_edit.record_location!
      redirect_to guest_edit_thanks_path(params[:token])
    else
      @submitted = submitted_params
      render :show, status: :unprocessable_entity
    end
  end

  # Reachable even after a single-use link is spent, so the person who just
  # submitted still gets their confirmation. Reveals nothing about the link.
  def thanks
    @edit_link = EditLink.find_by(token: params[:token].to_s)
    @can_submit_again = @edit_link&.usable?
  end

  private

  # Unknown, revoked and expired links all look identical to a visitor.
  def set_edit_link
    @edit_link = EditLink.find_usable(params[:token])
    render :unavailable, status: :not_found unless @edit_link
  end

  def set_translation
    @translation = @edit_link.translation
    render :nothing_to_edit, status: :not_found unless @translation
  end

  # The token is a bearer secret: keep it out of Referer headers and caches.
  # "same-origin" (not "no-referrer") so the form POST still carries a real
  # Origin header; with "no-referrer" browsers send `Origin: null` and Rails'
  # CSRF origin check rejects every submission. Other sites still get no Referer.
  def keep_token_private
    response.set_header("Referrer-Policy", "same-origin")
    response.set_header("Cache-Control", "no-store")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  def submitted_params = params.permit(:guest_name, :guest_email, :guest_phone, :translated_title, :translated_body)
  def translation_params = submitted_params.slice(:translated_title, :translated_body)
end
