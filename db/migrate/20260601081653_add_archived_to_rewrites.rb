class AddArchivedToRewrites < ActiveRecord::Migration[8.0]
  def change
    add_column :rewrites, :archived, :boolean, default: false, null: false
  end
end
