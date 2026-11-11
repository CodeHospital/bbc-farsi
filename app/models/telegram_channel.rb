# A publishing channel. Either a messenger whose bot API is
# Telegram-compatible — `<api_base_url>/bot<token>/sendMessage` with chat_id +
# text: Telegram itself, Bale (bale.ai), or a custom endpoint (another
# compatible provider, or a self-hosted Telegram Bot API server) — or one of
# the social platforms with their own APIs: WhatsApp (Cloud API), Instagram
# (Graph API) and TikTok (Content Posting API). All providers share this
# table, the Publisher/Autoposter queue and pacing, and the TelegramPost
# delivery log — only the outbound HTTP call differs (see #poster).
#
# What `token` / `channel_id` / `account_id` hold per provider:
#   telegram, bale, custom  bot token / chat id (@channel or -100…)
#   whatsapp                permanent access token / recipient phone number
#                           or group id / account_id = phone-number ID (sender)
#   instagram               access token / Instagram professional account ID
#   tiktok                  refresh token (rotated after each refresh) /
#                           optional @handle, for display only /
#                           client_key + client_secret = the TikTok app
class TelegramChannel < ApplicationRecord
  # `token` (the bot token) is excluded from version snapshots so it never
  # lingers in the audit trail (readable on the admin activity log page).
  has_paper_trail ignore: [ :token, :client_secret ]

  # Built-in presets. `custom` has no defaults: the admin supplies its API base
  # URL, a display name, and whether it accepts Telegram's HTML parse_mode.
  PROVIDERS = {
    "telegram" => { label: "Telegram", persian_label: "تلگرام", api_base_url: "https://api.telegram.org", message_format: "html" },
    "bale"     => { label: "Bale",     persian_label: "بله",    api_base_url: "https://tapi.bale.ai",     message_format: "plain" },
    "custom"   => { label: "Other Telegram-compatible API", persian_label: nil, api_base_url: nil, message_format: nil },
    "whatsapp"  => { label: "WhatsApp",  persian_label: "واتس‌اپ",   api_base_url: "https://graph.facebook.com/v23.0", message_format: "plain" },
    "instagram" => { label: "Instagram", persian_label: "اینستاگرام", api_base_url: "https://graph.facebook.com/v23.0", message_format: "plain" },
    "tiktok"    => { label: "TikTok",    persian_label: "تیک‌تاک",    api_base_url: "https://open.tiktokapis.com",     message_format: "plain" }
  }.freeze
  # Providers speaking the Telegram bot API (`/bot<token>/sendMessage`).
  BOT_API_PROVIDERS = %w[telegram bale custom].freeze
  # Instagram and TikTok have no text-only posts: an article without a lead
  # image can't go out there.
  IMAGE_REQUIRED_PROVIDERS = %w[instagram tiktok].freeze
  # "html" sends parse_mode HTML (bold title); "plain" sends no parse_mode, for
  # providers that don't support it (Bale renders its own Markdown instead).
  MESSAGE_FORMATS = %w[html plain].freeze

  has_many :telegram_posts, dependent: :destroy
  # Feeds autoposting here just lose this channel as a target when it's
  # deleted, rather than blocking deletion on the join table's foreign key.
  has_many :feed_autopost_channels, dependent: :delete_all
  has_many :autoposting_feeds, through: :feed_autopost_channels, source: :feed

  normalizes :api_base_url, with: ->(url) { url.strip.chomp("/").presence }
  normalizes :custom_provider_name, :message_format, :account_id, :client_key, :client_secret, with: ->(value) { value.strip.presence }

  validates :name, presence: true
  validates :token, presence: true
  validates :channel_id, presence: true, unless: :tiktok?
  validates :provider, inclusion: { in: PROVIDERS.keys }
  validates :api_base_url, format: { with: %r{\Ahttps?://[^\s/]+(/\S*)?\z}, message: "must be an http(s) URL" }, allow_nil: true
  validates :api_base_url, :custom_provider_name, :message_format, presence: true, if: :custom?
  validates :message_format, inclusion: { in: MESSAGE_FORMATS }, allow_nil: true
  validates :account_id, presence: { message: "(phone-number ID) is required for WhatsApp" }, if: :whatsapp?
  validates :client_key, :client_secret, presence: { message: "is required for TikTok" }, if: :tiktok?

  scope :enabled, -> { where(enabled: true) }
  scope :autopost, -> { enabled.where(autopost: true) }

  def telegram? = provider == "telegram"
  def bale? = provider == "bale"
  def custom? = provider == "custom"
  def whatsapp? = provider == "whatsapp"
  def instagram? = provider == "instagram"
  def tiktok? = provider == "tiktok"
  def bot_api? = BOT_API_PROVIDERS.include?(provider)
  def requires_image? = IMAGE_REQUIRED_PROVIDERS.include?(provider)

  def provider_label = custom? ? custom_provider_name.to_s : PROVIDERS.dig(provider, :label).to_s
  def provider_persian_label = custom? ? custom_provider_name.to_s : PROVIDERS.dig(provider, :persian_label).to_s

  # The endpoint actually called: an explicit override (e.g. a self-hosted
  # Telegram Bot API server), else the provider's own default.
  def effective_api_base_url = api_base_url.presence || PROVIDERS.dig(provider, :api_base_url)

  # Only a custom provider's format is configurable; the presets are fixed.
  def effective_message_format = custom? ? message_format : PROVIDERS.dig(provider, :message_format)

  # Name for pickers that mix providers. Telegram stays the bare name (the
  # long-standing default); every other provider gets a suffix.
  def display_name = telegram? ? name : "#{name} (#{provider_label})"
  def persian_display_name = telegram? ? name : "#{name} (#{provider_persian_label})"

  # Whether this channel currently accepts autoposted content — enabled AND its
  # own Autopost toggle on. See Feed#autopost_channels.
  def accepts_autopost? = enabled? && autopost?

  # The service that actually sends a message to this channel. Telegram keeps
  # the telegram-bot-ruby client; the other Telegram-compatible providers go
  # through the plain HTTP BotApiPoster (see there for why); the social
  # platforms each have their own poster.
  def poster
    case provider
    when "telegram"  then TelegramPoster.new
    when "whatsapp"  then WhatsappPoster.new
    when "instagram" then InstagramPoster.new
    when "tiktok"    then TiktokPoster.new
    else BotApiPoster.new
    end
  end
end
