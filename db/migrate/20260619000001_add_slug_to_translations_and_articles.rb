class AddSlugToTranslationsAndArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :translations, :slug, :string
    add_index  :translations, :slug, unique: true

    add_column :articles, :slug, :string
    add_index  :articles, :slug, unique: true
  end
end
