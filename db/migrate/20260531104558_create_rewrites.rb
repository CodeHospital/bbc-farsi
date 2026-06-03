class CreateRewrites < ActiveRecord::Migration[8.0]
  def change
    create_table :rewrites do |t|
      t.references :article, null: false, foreign_key: true
      t.text :content
      t.string :llm_model
      t.string :status, null: false, default: 'pending'
      t.text :error_message

      t.timestamps
    end
  end
end
