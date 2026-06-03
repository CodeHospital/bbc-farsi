class Admin::TelegramPostsController < Admin::BaseController
  include Pagy::Backend

  def index
    @pagy, @posts = pagy(
      TelegramPost.includes(:translation, :telegram_channel).order(created_at: :desc)
    )
  end

  def show
    @post = TelegramPost.includes(:translation, :telegram_channel).find(params[:id])
  end
end
