class CreateSearchQueries < ActiveRecord::Migration[8.0]
  def change
    create_table :search_queries do |t|
      t.string   :keyword,      null: false
      t.string   :edition,      limit: 2, null: false, default: "fa"
      t.integer  :results_count, null: false, default: 0
      t.datetime :created_at,   null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :search_queries, :keyword
    add_index :search_queries, :created_at
  end
end
