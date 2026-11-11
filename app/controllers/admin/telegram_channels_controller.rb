class Admin::TelegramChannelsController < Admin::BaseController
  before_action :require_admin!
  before_action :set_channel, only: %i[edit update destroy toggle]

  SORT_COLUMNS = {
    "name"     => "telegram_channels.name",
    "provider" => "telegram_channels.provider",
    "enabled"  => "telegram_channels.enabled",
    "autopost" => "telegram_channels.autopost"
  }.freeze

  def index
    column    = SORT_COLUMNS[params[:sort]] || "telegram_channels.name"
    direction = params[:dir] == "asc" ? "asc" : "desc"
    @channels = TelegramChannel.order(Arel.sql("#{column} #{direction}"))
  end

  def new
    @channel = TelegramChannel.new
  end

  def create
    @channel = TelegramChannel.new(channel_params)
    if @channel.save
      redirect_to admin_telegram_channels_path, notice: "Channel created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @channel.update(channel_params)
      redirect_to admin_telegram_channels_path, notice: "Channel updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @channel.destroy
    redirect_to admin_telegram_channels_path, notice: "Channel deleted."
  end

  def toggle
    @channel.update!(enabled: !@channel.enabled)
    redirect_to admin_telegram_channels_path, notice: "Channel #{@channel.enabled? ? 'enabled' : 'disabled'}."
  end

  private

  def set_channel = @channel = TelegramChannel.find(params[:id])
  # The TikTok client secret is never rendered back into the form, so a blank
  # one on update means "keep the saved secret".
  def channel_params
    permitted_params = raw_channel_params
    permitted_params.delete(:client_secret) if @channel&.persisted? && permitted_params[:client_secret].blank?
    permitted_params
  end

  def raw_channel_params = params.require(:telegram_channel).permit(:name, :provider, :custom_provider_name, :api_base_url, :message_format,
                                                                        :token, :channel_id, :account_id, :client_key, :client_secret,
                                                                        :enabled, :autopost)
end
