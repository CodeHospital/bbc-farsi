# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_07_03_000001) do
  create_table "article_views", force: :cascade do |t|
    t.integer "article_id", null: false
    t.integer "translation_id"
    t.string "country_code", limit: 2
    t.string "edition", limit: 2, default: "fa", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "country_name"
    t.string "city_name"
    t.index ["article_id", "created_at"], name: "index_article_views_on_article_id_and_created_at"
    t.index ["article_id"], name: "index_article_views_on_article_id"
    t.index ["country_code"], name: "index_article_views_on_country_code"
    t.index ["created_at"], name: "index_article_views_on_created_at"
  end

  create_table "articles", force: :cascade do |t|
    t.integer "feed_id", null: false
    t.string "title"
    t.string "url"
    t.text "description"
    t.datetime "published_at"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "archived", default: false, null: false
    t.string "slug"
    t.index ["feed_id"], name: "index_articles_on_feed_id"
    t.index ["slug"], name: "index_articles_on_slug", unique: true
    t.index ["url"], name: "index_articles_on_url", unique: true
  end

  create_table "feeds", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "category"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "bbc", null: false
    t.index ["url"], name: "index_feeds_on_url", unique: true
  end

  create_table "ip_geolocations", force: :cascade do |t|
    t.string "ip", null: false
    t.string "country_name"
    t.string "city_name"
    t.integer "lookups_count", default: 0, null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_name"], name: "index_ip_geolocations_on_country_name"
    t.index ["ip"], name: "index_ip_geolocations_on_ip", unique: true
  end

  create_table "ollama_servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "url", null: false
    t.boolean "enabled", default: true, null: false
    t.text "rewrite_models"
    t.text "translate_models"
    t.text "refine_models"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rewrites", force: :cascade do |t|
    t.integer "article_id", null: false
    t.text "content"
    t.string "llm_model"
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: false, null: false
    t.boolean "archived", default: false, null: false
    t.integer "ollama_server_id"
    t.string "rewritten_title"
    t.index ["article_id"], name: "index_rewrites_on_article_id"
    t.index ["ollama_server_id"], name: "index_rewrites_on_ollama_server_id"
  end

  create_table "search_queries", force: :cascade do |t|
    t.string "keyword", null: false
    t.string "edition", limit: 2, default: "fa", null: false
    t.integer "results_count", default: 0, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["created_at"], name: "index_search_queries_on_created_at"
    t.index ["keyword"], name: "index_search_queries_on_keyword"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", limit: 1024, null: false
    t.binary "value", limit: 536870912, null: false
    t.datetime "created_at", null: false
    t.integer "key_hash", limit: 8, null: false
    t.integer "byte_size", limit: 4, null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "tasks", force: :cascade do |t|
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.string "target_type", null: false
    t.integer "target_id", null: false
    t.integer "ollama_server_id"
    t.string "model"
    t.json "requests"
    t.json "responses"
    t.boolean "chain_translate", default: true, null: false
    t.boolean "chain_autopost", default: true, null: false
    t.text "error_message"
    t.integer "attempts", default: 0, null: false
    t.datetime "claimed_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "priority", default: 0, null: false
    t.boolean "chain_refine", default: true, null: false
    t.string "external_job_id"
    t.index ["external_job_id"], name: "index_tasks_on_external_job_id"
    t.index ["ollama_server_id"], name: "index_tasks_on_ollama_server_id"
    t.index ["status", "created_at"], name: "index_tasks_on_status_and_created_at"
    t.index ["status", "priority", "created_at"], name: "index_tasks_on_status_and_priority_and_created_at"
    t.index ["target_type", "target_id"], name: "index_tasks_on_target_type_and_target_id"
  end

  create_table "telegram_channels", force: :cascade do |t|
    t.string "name"
    t.string "token"
    t.string "channel_id"
    t.boolean "enabled", default: true, null: false
    t.boolean "autopost", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "telegram_posts", force: :cascade do |t|
    t.integer "translation_id", null: false
    t.integer "telegram_channel_id", null: false
    t.datetime "posted_at"
    t.string "status"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["telegram_channel_id"], name: "index_telegram_posts_on_telegram_channel_id"
    t.index ["translation_id"], name: "index_telegram_posts_on_translation_id"
  end

  create_table "translations", force: :cascade do |t|
    t.integer "article_id", null: false
    t.integer "rewrite_id", null: false
    t.string "translated_title"
    t.text "translated_body"
    t.string "llm_model"
    t.string "prompt_name"
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: false, null: false
    t.boolean "archived", default: false, null: false
    t.integer "ollama_server_id"
    t.string "slug"
    t.index ["article_id"], name: "index_translations_on_article_id"
    t.index ["ollama_server_id"], name: "index_translations_on_ollama_server_id"
    t.index ["rewrite_id"], name: "index_translations_on_rewrite_id"
    t.index ["slug"], name: "index_translations_on_slug", unique: true
  end

  add_foreign_key "article_views", "articles"
  add_foreign_key "articles", "feeds"
  add_foreign_key "rewrites", "articles"
  add_foreign_key "telegram_posts", "telegram_channels"
  add_foreign_key "telegram_posts", "translations"
  add_foreign_key "translations", "articles"
  add_foreign_key "translations", "rewrites"
end
