class CreateSolidCableMessages < ActiveRecord::Migration[8.0]
  # Solid Cable lives in the primary database (same pattern as Solid Cache —
  # see 20260609000001_create_solid_cache_entries.rb) rather than a separate
  # `cable` database, so Action Cable broadcasts work off a single DB with no
  # extra infra (H-11 from plan2.md: the previous `async` adapter only
  # delivered broadcasts within the same process, silently dropping anything
  # broadcast from a rake task/console, and would break with more than one
  # web process).
  def change
    create_table :solid_cable_messages do |t|
      t.binary   :channel,      limit: 1024,        null: false
      t.binary   :payload,      limit: 536_870_912, null: false
      t.datetime :created_at,                        null: false
      t.integer  :channel_hash, limit: 8,            null: false
    end

    add_index :solid_cable_messages, :channel
    add_index :solid_cable_messages, :channel_hash
    add_index :solid_cable_messages, :created_at
  end
end
