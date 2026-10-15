# Bootstrap admin credentials (see AdminBootstrap) — required in Rails
# credentials (admin_username / admin_password / admin_email). Checked directly
# here (rather than through AdminBootstrap) since config/initializers/*.rb run
# before the app's autoloader is set up, and referencing an autoloaded app/
# constant at that point raises NameError (see config/initializers/action_mailer.rb).
unless Rails.env.test?
  required = %i[admin_username admin_password admin_email]
  missing  = required.reject { |credential_key| Rails.application.credentials.dig(credential_key).present? }
  raise "Missing required admin bootstrap credentials (set via bin/rails credentials:edit): #{missing.join(', ')}" if missing.any?
end
