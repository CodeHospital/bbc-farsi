# Persian version of the analyzer's reasoning sentence (the model's
# "farsi_reasoning" JSON field), stored beside the English analysis_reasoning.
class AddAnalysisReasoningFaToArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :articles, :analysis_reasoning_fa, :text
  end
end
