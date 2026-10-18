class AddImageUrlToArticles < ActiveRecord::Migration[8.0]
  # The article's lead image is stored instead of being looked up while a
  # visitor's page renders. `image_url` starts as the feed's own image
  # (media:thumbnail / media:content / enclosure) and is upgraded to the
  # source page's og:image by ArticleImageResolver, which stamps
  # `image_resolved_at` (also its claim marker) once it has looked.
  def change
    add_column :articles, :image_url, :string
    add_column :articles, :image_resolved_at, :datetime
    add_index :articles, :image_resolved_at
  end
end
