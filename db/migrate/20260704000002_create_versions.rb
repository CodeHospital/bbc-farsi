# Standard PaperTrail versions table: one row per create/update/destroy on a
# tracked model, holding a serialized snapshot of the record's prior state
# (`object`) plus the changed attributes (`object_changes`) and who did it
# (`whodunnit`, a User id set from the current admin session).
class CreateVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :versions do |t|
      t.string   :item_type, null: false
      t.integer  :item_id,   null: false
      t.string   :event,     null: false
      t.string   :whodunnit
      t.text     :object
      t.text     :object_changes
      t.datetime :created_at
    end

    add_index :versions, %i[item_type item_id]
  end
end
