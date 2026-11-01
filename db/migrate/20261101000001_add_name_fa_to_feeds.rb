class AddNameFaToFeeds < ActiveRecord::Migration[8.0]
  # The Persian name shown for a feed in the public stories (story bar, viewer,
  # feed page). Blank falls back to `name`.
  def change
    add_column :feeds, :name_fa, :string
  end
end
