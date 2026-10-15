# Configuration for outgoing mail (password resets, etc.), sent via Resend's
# SMTP relay (smtp.resend.com) through ActionMailer's :smtp delivery method —
# no extra gem needed beyond what Rails ships with.
#
# Read from Rails credentials (see AppCredentials):
#   resend_api_key  Resend API key (used as the SMTP password)
#   sender_email    e.g. "Khabarestan <noreply@yourdomain.com>"
#
# See config/initializers/action_mailer.rb (applies these as smtp_settings)
# and Llmarkt.app_base_url (reused here for mailer default_url_options).
module MailerConfig
  module_function

  def api_key
    AppCredentials.fetch(:resend_api_key).presence
  end

  def from_address
    AppCredentials.fetch(:sender_email).presence
  end

  def enabled?
    api_key.present? && from_address.present?
  end
end
