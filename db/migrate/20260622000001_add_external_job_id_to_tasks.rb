class AddExternalJobIdToTasks < ActiveRecord::Migration[8.0]
  # Stores the llmarkt (vibeearning) job id for the request currently in flight,
  # for traceability/debugging. The webhook routing itself uses a signed token,
  # not this column.
  def change
    add_column :tasks, :external_job_id, :string
    add_index  :tasks, :external_job_id
  end
end
