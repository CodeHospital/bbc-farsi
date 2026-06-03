class CreateFeeds < ActiveRecord::Migration[8.0]
  def change
    create_table :feeds do |t|
      t.string :name
      t.string :url
      t.string :category
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end
    add_index :feeds, :url, unique: true
  end
end
