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
    counts_by_article_and_edition = scope
      .joins(:article)
      .group("article_views.article_id", "articles.title", "article_views.edition")
      .count("article_views.id")

    @top_articles = counts_by_article_and_edition
      .each_with_object({}) do |((article_id, title, edition), count), rows|
        row = rows[article_id] ||= { article_id:, title:, fa_count: 0, en_count: 0 }
        row[edition == "en" ? :en_count : :fa_count] += count
      end
      .values
      .map { |row| row.merge(count: row[:fa_count] + row[:en_count]) }
      .sort_by { |row| -row[:count] }
      .first(15)
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
