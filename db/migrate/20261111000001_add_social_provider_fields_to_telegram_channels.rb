# Credentials the WhatsApp / Instagram / TikTok providers need beyond the
# shared token + channel_id (see TelegramChannel::PROVIDERS):
# - account_id:    WhatsApp Cloud API phone-number ID (the sender).
# - client_key /
#   client_secret: TikTok app credentials, used to refresh the access token.
class AddSocialProviderFieldsToTelegramChannels < ActiveRecord::Migration[8.0]
  def change
    add_column :telegram_channels, :account_id, :string
    add_column :telegram_channels, :client_key, :string
    add_column :telegram_channels, :client_secret, :string
  end
end
