class AddOllamaServerToRewritesAndTranslations < ActiveRecord::Migration[8.0]
  def change
    add_column :rewrites,     :ollama_server_id, :integer
    add_column :translations, :ollama_server_id, :integer
    add_index  :rewrites,     :ollama_server_id
    add_index  :translations, :ollama_server_id
  end
end
