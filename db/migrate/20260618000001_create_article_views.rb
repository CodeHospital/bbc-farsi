class CreateArticleViews < ActiveRecord::Migration[8.0]
  def change
    create_table :article_views do |t|
      t.references :article, null: false, foreign_key: true
      t.integer    :translation_id
      t.string     :country_code, limit: 2
      t.string     :edition,      limit: 2, null: false, default: "fa"
      t.datetime   :created_at,   null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :article_views, %i[article_id created_at]
    add_index :article_views, :country_code
    add_index :article_views, :created_at
  end
end
