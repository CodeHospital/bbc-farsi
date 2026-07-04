# The very first admin account — used once by `db/seeds.rb` to create the
# first admin `User` row when the `users` table is empty (after that, admins
# manage everyone, including themselves, from /admin/users).
#
# Credentials are read from Rails credentials first, then ENV as a fallback:
#   credentials.admin_username / ENV["ADMIN_USERNAME"]
#   credentials.admin_password / ENV["ADMIN_PASSWORD"]
#   credentials.admin_email    / ENV["ADMIN_EMAIL"]
module AdminBootstrap
  module_function

  def username
    fetch(:admin_username, "ADMIN_USERNAME").presence
  end

  def password
    fetch(:admin_password, "ADMIN_PASSWORD").presence
  end

  def email
    fetch(:admin_email, "ADMIN_EMAIL").presence
  end

  def configured?
    username.present? && password.present? && email.present?
  end

  def fetch(credential_key, env_key)
    Rails.application.credentials.dig(credential_key) || ENV[env_key]
  end
  private_class_method :fetch
end
