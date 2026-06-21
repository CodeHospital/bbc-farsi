class AddRewrittenTitleToRewrites < ActiveRecord::Migration[8.0]
  def change
    add_column :rewrites, :rewritten_title, :string
  end
end
