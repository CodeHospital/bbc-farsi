class Admin::DashboardController < Admin::BaseController
  def index
    @counts = {
      feeds:            Feed.count,
      articles:         Article.count,
      rewrites:         Rewrite.count,
      translations:     Translation.count,
      telegram_channels: TelegramChannel.count,
      telegram_posts:   TelegramPost.count
    }
    @recent_articles    = Article.order(created_at: :desc).limit(10)
    @recent_posts       = TelegramPost.includes(:translation, :telegram_channel).order(created_at: :desc).limit(10)
    @pending_articles   = Article.where(status: %w[pending rewriting translating]).count
    @error_articles     = Article.where(status: "error").count
  end
end
