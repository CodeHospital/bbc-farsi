class CreateSkipPhrases < ActiveRecord::Migration[8.0]
  # Admin-editable phrases that make feed ingestion skip an entry (replaces the
  # hard-coded Article::IGNORE_* lists). `match_field` is "title" or "url";
  # matching is a case-insensitive substring. The previous built-in lists are
  # inserted here so behaviour is unchanged after migrating.
  DEFAULT_PHRASES = {
    "title" => %w[Watch: Assignment: Speak: Podcast: Newsletter: Trending:],
    "url"   => %w[iplayer programmes sounds]
  }.freeze

  def change
    create_table :skip_phrases do |t|
      t.string  :phrase,      null: false
      t.string  :match_field, null: false, default: "title"
      t.boolean :enabled,     null: false, default: true
      t.timestamps
    end
    add_index :skip_phrases, %i[match_field phrase], unique: true

    reversible do |direction|
      direction.up do
        now = Time.current
        DEFAULT_PHRASES.each do |match_field, phrases|
          phrases.each do |phrase|
            execute("INSERT INTO skip_phrases (phrase, match_field, enabled, created_at, updated_at) " \
                    "VALUES (#{quote(phrase)}, #{quote(match_field)}, #{quoted_true}, #{quote(now)}, #{quote(now)})")
          end
        end
      end
    end
  end
end
