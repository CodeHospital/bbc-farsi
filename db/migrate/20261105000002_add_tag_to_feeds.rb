class AddTagToFeeds < ActiveRecord::Migration[8.0]
  # The feed's own tag: an ordinary, editable Tag attached to every article
  # taken from that feed (see Feed#default_tag). Separate from
  # 20261105000001_create_tags because that migration had already been applied.
  def change
    add_reference :feeds, :tag, foreign_key: true
  end
end
