class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks do |t|
      t.string  :kind,            null: false
      t.string  :status,          null: false, default: "pending"
      t.string  :target_type,     null: false
      t.integer :target_id,       null: false
      t.integer :ollama_server_id
      t.string  :model
      t.json    :requests
      t.json    :responses
      t.boolean :chain_translate, null: false, default: true
      t.boolean :chain_autopost,  null: false, default: true
      t.text    :error_message
      t.integer :attempts,        null: false, default: 0
      t.datetime :claimed_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :tasks, [:status, :created_at]
    add_index :tasks, [:target_type, :target_id]
    add_index :tasks, :ollama_server_id
  end
end
