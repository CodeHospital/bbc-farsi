class CreateTelegramChannels < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_channels do |t|
      t.string :name
      t.string :token
      t.string :channel_id
      t.boolean :enabled, default: true, null: false
      t.boolean :autopost, default: false, null: false

      t.timestamps
    end
  end
end
