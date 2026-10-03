class Admin::FeedsController < Admin::BaseController
  before_action :require_admin!
  before_action :set_feed, only: %i[edit update destroy toggle fetch schedule autopost_channel]
  before_action :set_autopost_channel_options, only: %i[index toggle fetch schedule autopost_channel]

  def index
    load_filtered_feeds
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

  SEED_METHODS = {
    "bbc"        => [ :seed_bbc_feeds!, "BBC" ],
    "nyt"        => [ :seed_nyt_feeds!, "NYT" ],
    "adhocnews"  => [ :seed_adhocnews_feeds!, "Ad Hoc News" ],
    "heise"      => [ :seed_heise_feeds!, "heise" ],
    "germannews"    => [ :seed_germannews_feeds!, "German News" ],
    "australianews" => [ :seed_australianews_feeds!, "Australian News" ],
    "israelnews"    => [ :seed_israelnews_feeds!, "Israel News" ]
  }.freeze

  def seed
    method, label = SEED_METHODS.fetch(params[:source], SEED_METHODS["bbc"])
    Feed.public_send(method)
    redirect_to admin_feeds_path, notice: "#{label} feeds seeded — #{Feed.count} feeds total."
  end

  def toggle
    @feed.update!(enabled: !@feed.enabled)
    # A feed toggled out of the currently active filter (e.g. disabling a feed
    # while viewing "Enabled" only) should disappear from the turbo-stream
    # response instead of lingering with a stale row.
    @feed_matches_filter = feed_matches_filter?(@feed)
    @telegram_posts_counts_by_feed_id = telegram_posts_counts_by_feed_id
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to admin_feeds_path, notice: "Feed #{@feed.enabled? ? 'enabled' : 'disabled'}." }
    end
  end

  # Sets (or clears, on a blank value) a feed's scheduled fetch hour straight
  # from the index row. An out-of-range hour just re-renders the unchanged row.
  def schedule
    @feed.reload unless @feed.update(fetch_hour: params[:fetch_hour].presence)
    @telegram_posts_counts_by_feed_id = telegram_posts_counts_by_feed_id
    respond_to do |format|
      format.turbo_stream
      format.html do
        redirect_back fallback_location: admin_feeds_path,
                      notice: "#{@feed.name} scheduled fetch: #{@feed.fetch_schedule_label}."
      end
    end
  end

  # Replaces a feed's set of autopost target channels (any provider) straight
  # from the index row's checkboxes; an empty set disables autoposting. An
  # unknown channel id leaves the set unchanged and just re-renders the row.
  def autopost_channel
    requested_channel_ids = Array(params[:autopost_target_channel_ids]).compact_blank.map(&:to_i).uniq
    if TelegramChannel.where(id: requested_channel_ids).count == requested_channel_ids.size
      @feed.update!(autopost_target_channel_ids: requested_channel_ids)
    end
    @feed.reload
    @telegram_posts_counts_by_feed_id = telegram_posts_counts_by_feed_id
    respond_to do |format|
      format.turbo_stream
      format.html do
        redirect_back fallback_location: admin_feeds_path,
                      notice: "#{@feed.name} autopost channels: #{@feed.autopost_channel_label}."
      end
    end
  end

  # Fetches this one feed synchronously and reports new/updated/skipped
  # counts (with a reason for every skipped entry) right on the index page.
  def fetch
    @fetch_result = FeedIngestor.run_one(@feed)
    load_filtered_feeds

    if @fetch_result[:error]
      flash.now[:alert] = "Fetch failed for #{@feed.name}: #{@fetch_result[:error]}"
    else
      flash.now[:notice] = "Fetched #{@feed.name}: #{@fetch_result[:new_count]} new, " \
                            "#{@fetch_result[:updated_count]} updated, #{@fetch_result[:skipped].size} skipped."
    end

    render :index
  end

  private

  def set_feed = @feed = Feed.find(params[:id])
  def feed_params = params.require(:feed).permit(:name, :url, :category, :source, :enabled, :fetch_hour, autopost_target_channel_ids: [])

  # Computed once per request instead of once per row — the inline autopost
  # checkboxes on every feed row need the same channel list.
  def set_autopost_channel_options
    @autopost_channel_options = TelegramChannel.order(:name).to_a
  end

  def load_filtered_feeds
    @enabled_filter   = params[:enabled].presence || "enabled"
    @enabled_counts   = Feed.group(:enabled).count
    @source_counts    = Feed.group(:source).count
    @category_counts  = Feed.group(:category).count

    @feeds = filtered_feeds.includes(:autopost_target_channels).order(:name)
    @telegram_posts_counts_by_feed_id = telegram_posts_counts_by_feed_id
  end

  def filtered_feeds
    enabled_filter = params[:enabled].presence || "enabled"

    feeds = Feed.all
    feeds = feeds.where(enabled: true)  if enabled_filter == "enabled"
    feeds = feeds.where(enabled: false) if enabled_filter == "disabled"
    feeds = feeds.where(source: params[:source])     if params[:source].present?
    feeds = feeds.where(category: params[:category]) if params[:category].present?
    feeds
  end

  def feed_matches_filter?(feed)
    filtered_feeds.exists?(feed.id)
  end

  # One grouped query for all feeds, instead of an N+1 count per row. Counts
  # distinct posted *articles*, so a story sent to both a Telegram and a Bale
  # channel (or to several channels) counts once and "Posted %" stays <= 100%.
  def telegram_posts_counts_by_feed_id
    TelegramPost.posted
                .joins(translation: :article)
                .group("articles.feed_id")
                .distinct
                .count("articles.id")
  end
end
