class CreatePendingEdits < ActiveRecord::Migration[8.0]
  # Edit approval workflow. Editors flagged `requires_edit_approval` can't save
  # Translation/Rewrite edits directly; their change is stored as a
  # PendingEdit (proposed values + the values they were editing against) until
  # an admin or an unrestricted editor approves or rejects it.
  def change
    add_column :users, :requires_edit_approval, :boolean, default: false, null: false

    create_table :pending_edits do |t|
      t.references :editable, polymorphic: true, null: false
      t.references :author,   null: false, foreign_key: { to_table: :users }
      t.references :reviewer, foreign_key: { to_table: :users }
      t.json     :proposed_changes, null: false, default: {}
      t.json     :base_values,      null: false, default: {}
      t.string   :status,           null: false, default: "pending"
      t.text     :review_note
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :pending_edits, :status
  end
end
