class AddPriorityToTelegramPosts < ActiveRecord::Migration[8.0]
  # Queued posts are delivered highest priority first, then oldest first.
  # Priority 0 is the normal end-of-queue behaviour; "post first" bumps a post
  # above everything currently queued on its channel.
  def change
    add_column :telegram_posts, :priority, :integer, default: 0, null: false
  end
end
