# Resend SMTP relay for outgoing mail (password resets, etc.) — see
# MailerConfig for where credentials/ENV come from. Skipped in test, where
# config/environments/test.rb sets delivery_method to :test instead so specs
# never attempt a real network connection.
#
# Deferred to `to_prepare` (runs once at the end of boot, after the main
# Zeitwerk autoloader is fully set up, and again on every reload in
# development) rather than run directly here: at the point
# `config/initializers/*.rb` files load, application constants like
# MailerConfig/Llmarkt aren't autoloadable yet and referencing them raises
# NameError. See the Rails "Autoloading and Reloading Constants" guide.
Rails.application.config.to_prepare do
  next if Rails.env.test?

  config = Rails.application.config.action_mailer

  # Only actually attempt delivery once Resend is configured — otherwise mail
  # would try (and fail) to connect to localhost:25, ActionMailer's default.
  config.raise_delivery_errors = true
  config.perform_deliveries    = MailerConfig.enabled?

  if MailerConfig.enabled?
    config.delivery_method = :smtp
    config.smtp_settings = {
      address:              "smtp.resend.com",
      port:                 587,
      domain:               (URI.parse(Llmarkt.app_base_url).host if Llmarkt.app_base_url.present?),
      user_name:            "resend",
      password:             MailerConfig.api_key,
      authentication:       :plain,
      enable_starttls_auto: true
    }
  end

  if Llmarkt.app_base_url.present?
    uri = URI.parse(Llmarkt.app_base_url)
    config.default_url_options = { host: uri.host, port: uri.port, protocol: uri.scheme }
  end
end
