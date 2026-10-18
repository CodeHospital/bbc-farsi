class AddAnalyzeModelsToOllamaServers < ActiveRecord::Migration[8.0]
  # Models used for the AI bias/fact analysis task, picked per server like
  # rewrite/translate/refine. Blank everywhere = fall back to the rewrite
  # model (the previous behaviour).
  def change
    add_column :ollama_servers, :analyze_models, :text
  end
end
