class AddUniqueIndexToTelegramPosts < ActiveRecord::Migration[8.0]
  # M-4 from plan2.md: TelegramPost "already posted" uniqueness was only
  # enforced by application-level lookup (find_or_initialize_by), so the
  # autopost sweep, the translate/refine task chain, and the Telegram admin
  # bot could race into duplicate posts to the same channel. A DB-level
  # unique constraint backs the new Publisher service's claim-then-post
  # pattern (see app/services/publisher.rb) and the matching model
  # validation on TelegramPost.
  def change
    add_index :telegram_posts, [ :translation_id, :telegram_channel_id ], unique: true,
      name: "index_telegram_posts_on_translation_and_channel"
  end
end
