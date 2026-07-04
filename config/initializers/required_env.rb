# Bootstrap admin credentials (see AdminBootstrap) — required via Rails
# credentials OR ENV, either source is fine. Checked directly here (rather
# than through AdminBootstrap) since config/initializers/*.rb run before the
# app's autoloader is set up, and referencing an autoloaded app/ constant at
# that point raises NameError (see config/initializers/action_mailer.rb).
unless Rails.env.test?
  required = { "ADMIN_USERNAME" => :admin_username, "ADMIN_PASSWORD" => :admin_password, "ADMIN_EMAIL" => :admin_email }
  missing  = required.reject { |env_key, cred_key| ENV[env_key].present? || Rails.application.credentials.dig(cred_key).present? }
  raise "Missing required admin bootstrap credentials (set via Rails credentials or ENV): #{missing.keys.join(', ')}" if missing.any?
end
