class Admin::AnalyticsController < Admin::BaseController
  PERIODS = { "7" => "Last 7 days", "30" => "Last 30 days", "90" => "Last 90 days" }.freeze

  def show
    unless ArticleView.table_exists?
      @missing_migration = true
      return
    end

    @period_days = PERIODS.key?(params[:period]) ? params[:period] : "7"
    since = @period_days.to_i.days.ago
    scope = ArticleView.where(created_at: since..)

    @total_count = scope.count
    @by_edition  = scope.group(:edition).count
    @by_country  = scope.where.not(country_code: nil)
                        .group(:country_code)
                        .order("count_all DESC")
                        .limit(15)
                        .count
    @top_articles = scope
      .joins(:article)
      .group("article_views.article_id", "articles.title")
      .order("count(article_views.id) DESC")
      .limit(15)
      .count("article_views.id")
      .map { |(article_id, title), count| { article_id:, title:, count: } }
    @daily_views = scope
      .group("DATE(article_views.created_at)")
      .order("DATE(article_views.created_at)")
      .count

    if SearchQuery.table_exists?
      search_scope = SearchQuery.where(created_at: since..)
      @top_searches = search_scope
        .group(:keyword)
        .order("count_all DESC")
        .limit(20)
        .count
      @search_count = search_scope.count
    end
  end
end
