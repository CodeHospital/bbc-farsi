class EnsureUniqueIndexOnTelegramPosts < ActiveRecord::Migration[8.0]
  # 20260716000001 added this unique index, but db/schema.rb was never updated
  # to include it. Any database created from schema.rb since then (a fresh
  # `db:prepare` / `db:schema:load`, e.g. a first production deploy) got every
  # migration marked as run *without* the index — so Publisher's claim-then-
  # post race protection (plan2.md M-4) silently had no DB backing there.
  #
  # Idempotent: a no-op wherever the index already exists. Where it's missing,
  # duplicate translation+channel rows may have accumulated, which would make
  # the unique index fail to build, so those are collapsed first — keeping the
  # "posted" row if there is one (it's the delivery record), else the oldest.
  INDEX_NAME = "index_telegram_posts_on_translation_and_channel".freeze

  def up
    return if index_exists?(:telegram_posts, [ :translation_id, :telegram_channel_id ], name: INDEX_NAME)

    remove_duplicate_posts
    add_index :telegram_posts, [ :translation_id, :telegram_channel_id ], unique: true, name: INDEX_NAME
  end

  # Nothing to undo: the index itself belongs to 20260716000001, and the
  # removed duplicate rows can't be restored.
  def down; end

  private

  def remove_duplicate_posts
    duplicate_pairs = select_rows(<<~SQL)
      SELECT translation_id, telegram_channel_id FROM telegram_posts
      GROUP BY translation_id, telegram_channel_id HAVING COUNT(*) > 1
    SQL

    duplicate_pairs.each do |translation_id, telegram_channel_id|
      post_rows = select_all(<<~SQL).to_a
        SELECT id, status FROM telegram_posts
        WHERE translation_id = #{Integer(translation_id)} AND telegram_channel_id = #{Integer(telegram_channel_id)}
        ORDER BY id
      SQL

      kept_post = post_rows.find { |post_row| post_row["status"] == "posted" } || post_rows.first
      duplicate_post_ids = post_rows.map { |post_row| Integer(post_row["id"]) } - [ Integer(kept_post["id"]) ]
      execute("DELETE FROM telegram_posts WHERE id IN (#{duplicate_post_ids.join(', ')})")
    end
  end
end
