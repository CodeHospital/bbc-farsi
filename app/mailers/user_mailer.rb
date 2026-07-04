class UserMailer < ApplicationMailer
  def password_reset(user)
    @user  = user
    @token = user.generate_token_for(:password_reset)

    mail to: user.email, subject: "Reset your BBC Farsi admin password"
  end
end
