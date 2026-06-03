class AddActiveToRewrites < ActiveRecord::Migration[8.0]
  def change
    add_column :rewrites, :active, :boolean, default: false, null: false
  end
end
