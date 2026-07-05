class CreatePrompts < ActiveRecord::Migration[8.0]
  def change
    create_table :prompts do |t|
      t.string :key,  null: false
      t.string :name, null: false
      t.text   :description

      t.timestamps
    end
    add_index :prompts, :key, unique: true

    create_table :prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: true
      t.integer :number, null: false
      t.text :content, null: false
      t.references :user, foreign_key: true
      t.string :change_note

      t.timestamps
    end
    add_index :prompt_versions, [ :prompt_id, :number ], unique: true

    add_reference :prompts, :current_prompt_version, foreign_key: { to_table: :prompt_versions }

    create_table :prompt_version_usages do |t|
      t.references :prompt_version, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: true
      t.string :request_key, null: false

      t.timestamps
    end
    add_index :prompt_version_usages, [ :task_id, :request_key ], unique: true
  end
end
