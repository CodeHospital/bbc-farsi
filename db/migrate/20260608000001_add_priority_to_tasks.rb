class AddPriorityToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :priority, :integer, null: false, default: 0
    # Claim order is (status, priority DESC, created_at ASC); index the leading
    # columns so the worker's "next pending" lookup stays cheap.
    add_index :tasks, [ :status, :priority, :created_at ]
  end
end
