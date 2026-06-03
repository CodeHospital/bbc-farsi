class Admin::FeedsController < Admin::BaseController
  before_action :set_feed, only: %i[edit update destroy toggle]

  def index
    @feeds = Feed.order(:name)
  end

  def new
    @feed = Feed.new
  end

  def create
    @feed = Feed.new(feed_params)
    if @feed.save
      redirect_to admin_feeds_path, notice: "Feed created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @feed.update(feed_params)
      redirect_to admin_feeds_path, notice: "Feed updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed.destroy
    redirect_to admin_feeds_path, notice: "Feed deleted."
  end

  def seed
    Feed.seed_bbc_feeds!
    redirect_to admin_feeds_path, notice: "BBC feeds seeded — #{Feed.count} feeds total."
  end

  def toggle
    @feed.update!(enabled: !@feed.enabled)
    redirect_to admin_feeds_path, notice: "Feed #{@feed.enabled? ? 'enabled' : 'disabled'}."
  end

  private

  def set_feed = @feed = Feed.find(params[:id])
  def feed_params = params.require(:feed).permit(:name, :url, :category, :enabled)
end
