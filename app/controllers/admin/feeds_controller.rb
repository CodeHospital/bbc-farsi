class Admin::FeedsController < Admin::BaseController
  before_action :set_feed, only: %i[edit update destroy toggle fetch]

  SORT_COLUMNS = {
    "name"     => "feeds.name",
    "category" => "feeds.category",
    "source"   => "feeds.source",
    "enabled"  => "feeds.enabled"
  }.freeze

  def index
    @feeds = sorted_feeds
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
    if params[:source] == "nyt"
      Feed.seed_nyt_feeds!
      redirect_to admin_feeds_path, notice: "NYT feeds seeded — #{Feed.count} feeds total."
    else
      Feed.seed_bbc_feeds!
      redirect_to admin_feeds_path, notice: "BBC feeds seeded — #{Feed.count} feeds total."
    end
  end

  def toggle
    @feed.update!(enabled: !@feed.enabled)
    redirect_to admin_feeds_path, notice: "Feed #{@feed.enabled? ? 'enabled' : 'disabled'}."
  end

  # Fetches this one feed synchronously and reports new/updated/skipped
  # counts (with a reason for every skipped entry) right on the index page.
  def fetch
    @fetch_result = FeedIngestor.run_one(@feed)
    @feeds = sorted_feeds

    if @fetch_result[:error]
      flash.now[:alert] = "Fetch failed for #{@feed.name}: #{@fetch_result[:error]}"
    else
      flash.now[:notice] = "Fetched #{@feed.name}: #{@fetch_result[:new_count]} new, " \
                            "#{@fetch_result[:updated_count]} updated, #{@fetch_result[:skipped].size} skipped."
    end

    render :index
  end

  private

  def sorted_feeds
    column    = SORT_COLUMNS[params[:sort]] || "feeds.name"
    direction = params[:dir] == "asc" ? "asc" : "desc"
    Feed.order(Arel.sql("#{column} #{direction}"))
  end

  def set_feed = @feed = Feed.find(params[:id])
  def feed_params = params.require(:feed).permit(:name, :url, :category, :source, :enabled)
end
