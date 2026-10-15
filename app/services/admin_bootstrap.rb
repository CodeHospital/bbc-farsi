# The very first admin account — used once by `db/seeds.rb` to create the
# first admin `User` row when the `users` table is empty (after that, admins
# manage everyone, including themselves, from /admin/users).
#
# Read from Rails credentials (see AppCredentials): admin_username,
# admin_password, admin_email.
module AdminBootstrap
  module_function

  def username
    AppCredentials.fetch(:admin_username).presence
  end

  def password
    AppCredentials.fetch(:admin_password).presence
  end

  def email
    AppCredentials.fetch(:admin_email).presence
  end

  def configured?
    username.present? && password.present? && email.present?
  end
end
