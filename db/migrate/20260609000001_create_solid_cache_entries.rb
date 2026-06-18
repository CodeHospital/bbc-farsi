class CreateSolidCacheEntries < ActiveRecord::Migration[8.0]
  # Solid Cache now lives in the primary database (previously a separate `cache`
  # database loaded from db/cache_schema.rb). This creates its table here so
  # `db:prepare` / `db:migrate` provisions it in production PostgreSQL.
  def change
    create_table :solid_cache_entries do |t|
      t.binary   :key,        limit: 1024,      null: false
      t.binary   :value,      limit: 536_870_912, null: false
      t.datetime :created_at,                   null: false
      t.integer  :key_hash,   limit: 8,         null: false
      t.integer  :byte_size,  limit: 4,         null: false
    end

    add_index :solid_cache_entries, :key_hash, unique: true
    add_index :solid_cache_entries, :byte_size
    add_index :solid_cache_entries, [ :key_hash, :byte_size ]
  end
end
