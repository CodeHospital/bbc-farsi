class AddChainRefineToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :chain_refine, :boolean, null: false, default: true
  end
end
