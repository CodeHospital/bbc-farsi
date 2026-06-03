class CreateOllamaServers < ActiveRecord::Migration[8.0]
  def change
    create_table :ollama_servers do |t|
      t.string  :name,             null: false
      t.string  :url,              null: false
      t.boolean :enabled,          null: false, default: true
      t.text    :rewrite_models
      t.text    :translate_models
      t.text    :refine_models
      t.timestamps
    end
  end
end
