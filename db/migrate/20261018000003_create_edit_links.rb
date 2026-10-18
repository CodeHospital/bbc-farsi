class CreateEditLinks < ActiveRecord::Migration[8.0]
  # "Magic links": an admin/reviewer shares a secret URL that lets someone
  # without an account propose an edit to one article's published
  # translation. The visitor leaves their name, email and phone; the edit is
  # stored as a PendingEdit with no author user (guest_* columns identify
  # them) and goes through the normal approval queue.
  def change
    create_table :edit_links do |t|
      t.references :article,    null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string   :token,      null: false
      t.string   :note
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :edit_links, :token, unique: true

    change_column_null :pending_edits, :author_id, true
    add_reference :pending_edits, :edit_link, foreign_key: true
    add_column :pending_edits, :guest_name,  :string
    add_column :pending_edits, :guest_email, :string
    add_column :pending_edits, :guest_phone, :string
  end
end
