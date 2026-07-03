class AddSourceToFeeds < ActiveRecord::Migration[8.0]
  def change
    add_column :feeds, :source, :string, default: "bbc", null: false
  end
end
