class CreateTranslations < ActiveRecord::Migration[8.0]
  def change
    create_table :translations do |t|
      t.references :article, null: false, foreign_key: true
      t.references :rewrite, null: false, foreign_key: true
      t.string :translated_title
      t.text :translated_body
      t.string :llm_model
      t.string :prompt_name
      t.string :status, null: false, default: 'pending'
      t.text :error_message

      t.timestamps
    end
  end
end
