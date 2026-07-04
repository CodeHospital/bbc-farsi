class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :username,        null: false
      t.string  :name
      t.string  :password_digest, null: false
      t.string  :role,            null: false, default: "editor"
      t.boolean :active,          null: false, default: true

      t.timestamps
    end

    add_index :users, :username, unique: true
  end
end
