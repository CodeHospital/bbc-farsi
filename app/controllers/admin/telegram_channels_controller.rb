class Admin::TelegramChannelsController < Admin::BaseController
  before_action :require_admin!
  before_action :set_channel, only: %i[edit update destroy toggle]

  SORT_COLUMNS = {
    "name"     => "telegram_channels.name",
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
  def channel_params = params.require(:telegram_channel).permit(:name, :token, :channel_id, :enabled, :autopost)
end
