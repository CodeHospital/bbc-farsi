class CreateTelegramPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_posts do |t|
      t.references :translation, null: false, foreign_key: true
      t.references :telegram_channel, null: false, foreign_key: true
      t.datetime :posted_at
      t.string :status
      t.text :error_message

      t.timestamps
    end
  end
end
