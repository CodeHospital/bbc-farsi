class ApplicationMailer < ActionMailer::Base
  default from: -> { MailerConfig.from_address || "no-reply@localhost" }
  layout "mailer"
end
