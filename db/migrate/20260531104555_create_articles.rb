class CreateArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :articles do |t|
      t.references :feed, null: false, foreign_key: true
      t.string :title
      t.string :url
      t.text :description
      t.datetime :published_at
      t.string :status

      t.timestamps
    end
    add_index :articles, :url, unique: true
  end
end
