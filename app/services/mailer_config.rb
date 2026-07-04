# Configuration for outgoing mail (password resets, etc.), sent via Resend's
# SMTP relay (smtp.resend.com) through ActionMailer's :smtp delivery method —
# no extra gem needed beyond what Rails ships with.
#
# Credentials are read from Rails credentials first, then ENV as a fallback:
#   credentials.resend_api_key / ENV["RESEND_API_KEY"] Resend API key (used as the SMTP password)
#   credentials.sender_email   / ENV["SENDER_EMAIL"]   e.g. "BBC Farsi <noreply@yourdomain.com>"
#
# See config/initializers/action_mailer.rb (applies these as smtp_settings)
# and Llmarkt.app_base_url (reused here for mailer default_url_options).
module MailerConfig
  module_function

  def api_key
    fetch(:resend_api_key, "RESEND_API_KEY").presence
  end

  def from_address
    fetch(:sender_email, "SENDER_EMAIL").presence
  end

  def enabled?
    api_key.present? && from_address.present?
  end

  def fetch(credential_key, env_key)
    Rails.application.credentials.dig(credential_key) || ENV[env_key]
  end
  private_class_method :fetch
end
