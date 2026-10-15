class AddAnalysisToArticles < ActiveRecord::Migration[8.0]
  # AI analysis of the ORIGINAL article, run in parallel with the rewrite
  # (see ArticleAnalyzer). Political leaning is a three-way split and the
  # factual/speculative split is two-way; each split sums to 100. Admins can
  # edit every value. analysis_status: nil (never analyzed) / pending /
  # completed / failed.
  def change
    add_column :articles, :bias_left_percent,    :integer
    add_column :articles, :bias_center_percent,  :integer
    add_column :articles, :bias_right_percent,   :integer
    add_column :articles, :factual_percent,      :integer
    add_column :articles, :speculative_percent,  :integer
    add_column :articles, :analysis_reasoning,   :text
    add_column :articles, :analysis_status,      :string
    add_column :articles, :analyzed_at,          :datetime
  end
end
