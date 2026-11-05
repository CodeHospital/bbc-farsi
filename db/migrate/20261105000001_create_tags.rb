class CreateTags < ActiveRecord::Migration[8.0]
  # Editable, bilingual article tags. A tag has a Persian and an English name
  # (AI tagging can leave one blank until an editor fills it in); articles get
  # many tags through article_tags. `articles.tags_generated_at` records that
  # AI tagging ran for the article, so `bbc:tag` doesn't enqueue it again.
  def change
    create_table :tags do |t|
      t.string :name_fa
      t.string :name_en
      t.timestamps
    end
    add_index :tags, :name_fa, unique: true
    add_index :tags, :name_en, unique: true

    create_table :article_tags do |t|
      t.references :article, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :article_tags, %i[article_id tag_id], unique: true

    add_column :articles, :tags_generated_at, :datetime
  end
end
