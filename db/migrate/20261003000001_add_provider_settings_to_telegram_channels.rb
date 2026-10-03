class AddProviderSettingsToTelegramChannels < ActiveRecord::Migration[8.0]
  # Channels can live on any messenger whose bot API is Telegram-compatible
  # (`<api_base_url>/bot<token>/sendMessage` with chat_id + text): Telegram
  # itself, Bale (bale.ai), or a custom endpoint (another compatible provider,
  # or a self-hosted Telegram Bot API server). They all share this table, the
  # Publisher/Autoposter queue and the TelegramPost delivery log; see
  # TelegramChannel::PROVIDERS. Every existing row is a Telegram channel.
  def change
    add_column :telegram_channels, :provider, :string, default: "telegram", null: false
    # nil = the provider's default endpoint; required for the "custom" provider.
    add_column :telegram_channels, :api_base_url, :string
    # Display name for a "custom" provider (e.g. "Eitaa"); unused otherwise.
    add_column :telegram_channels, :custom_provider_name, :string
    # "html" or "plain" for a "custom" provider; Telegram is always HTML and
    # Bale always plain (it has no parse_mode).
    add_column :telegram_channels, :message_format, :string
  end
end
