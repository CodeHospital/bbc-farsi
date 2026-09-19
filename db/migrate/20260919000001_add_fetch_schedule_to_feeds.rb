class AddFetchScheduleToFeeds < ActiveRecord::Migration[8.0]
  def change
    # nil = not scheduled (the default); 0-23 = server-local hour of day.
    add_column :feeds, :fetch_hour, :integer
    # Claim marker so a feed is auto-fetched at most once per hour slot, no
    # matter how often the sweep runs (cron + in-process poller together).
    add_column :feeds, :last_scheduled_fetch_at, :datetime
  end
end
