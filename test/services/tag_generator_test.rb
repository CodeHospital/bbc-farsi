require "test_helper"

class TagGeneratorTest < ActiveSupport::TestCase
  test "process splits Persian | English pairs" do
    tags = TagGenerator.process("tags" => "ایران | Iran، اقتصاد | Economy\nتحریم|Sanctions")

    assert_equal [ { name_fa: "ایران", name_en: "Iran" }, { name_fa: "اقتصاد", name_en: "Economy" },
                   { name_fa: "تحریم", name_en: "Sanctions" } ], tags
  end

  test "process files single names (older Persian-only prompts) by their script" do
    tags = TagGenerator.process("tags" => "ایران, Oil")

    assert_equal [ { name_fa: "ایران", name_en: nil }, { name_fa: nil, name_en: "Oil" } ], tags
  end

  test "process strips think blocks, hashes, blanks and duplicates, and caps the count" do
    raw = "<think>reasoning</think>#ایران, ایران, , اقتصاد"
    assert_equal [ { name_fa: "ایران", name_en: nil }, { name_fa: "اقتصاد", name_en: nil } ], TagGenerator.process("tags" => raw)

    many = (1..9).map { |number| "برچسب#{number} | Tag#{number}" }.join(", ")
    assert_equal TagGenerator::MAX_TAGS, TagGenerator.process("tags" => many).size
  end

  test "requests builds a single keyed chat request from the translation text" do
    translation = create_translation(attrs: { translated_title: "عنوان", translated_body: "متن" })
    requests = TagGenerator.requests(translation)

    assert_equal 1, requests.size
    assert_equal "tags", requests.first[:key]
    assert_match "عنوان", requests.first[:messages].last[:content]
  end

  test "store links bilingual tags to the article after its feed's tag and marks it tagged" do
    article = create_article(feed: create_feed(name: "World", name_fa: "جهان"))
    feed_tag = article.feed.tag

    assert_equal [ feed_tag.name_fa ], TagGenerator.tags_for(article)
    refute TagGenerator.tagged?(article)

    TagGenerator.store(article.id, [ { name_fa: "ایران", name_en: "Iran" }, { name_fa: "اقتصاد", name_en: nil } ])

    article.reload
    assert TagGenerator.tagged?(article)
    assert_equal [ feed_tag.name_fa, "ایران", "اقتصاد" ], TagGenerator.tags_for(article)
    assert_equal [ feed_tag.name_en, "Iran" ], TagGenerator.tags_for(article, language: "en")
  end

  test "store reuses existing tags, fills a missing name, and keeps editor-added tags" do
    existing_tag = Tag.create!(name_fa: "ایران")
    editor_tag = Tag.create!(name_fa: "انتخابات", name_en: "Elections")
    article = create_article
    article.tags << editor_tag

    TagGenerator.store(article.id, [ { name_fa: "ایران", name_en: "Iran" } ])

    assert_equal "Iran", existing_tag.reload.name_en
    assert_equal 3, Tag.count # + the feed's tag
    assert_equal [ article.feed.tag, editor_tag, existing_tag ], article.reload.ordered_tags
  end

  test "untagged_candidates excludes already-tagged articles" do
    tagged = create_translation(attrs: { translated_title: "دارای برچسب" })
    tagged_with_nothing = create_translation(attrs: { translated_title: "بی‌برچسب ولی پردازش‌شده" })
    untagged = create_translation(attrs: { translated_title: "بدون برچسب" })
    TagGenerator.store(tagged.article_id, %w[برچسب])
    TagGenerator.store(tagged_with_nothing.article_id, [])

    candidate_ids = TagGenerator.untagged_candidates.map(&:article_id)

    assert_includes candidate_ids, untagged.article_id
    refute_includes candidate_ids, tagged.article_id
    refute_includes candidate_ids, tagged_with_nothing.article_id
  end

  test "untagged_candidates still includes articles that only have their feed's tag" do
    translation = create_translation

    assert_equal 1, translation.article.tags.count
    assert_includes TagGenerator.untagged_candidates.map(&:article_id), translation.article_id
  end

  test "backfill_feed_tags! gives older articles their feed's tag, once" do
    feed = create_feed(name: "World", name_fa: "جهان")
    article = create_article(feed:)
    article.article_tags.delete_all

    assert_equal 1, TagGenerator.backfill_feed_tags!
    assert_equal [ feed.reload.tag ], article.reload.tags.to_a
    assert_equal 0, TagGenerator.backfill_feed_tags!
  end

  test "import_cached_tags! moves pre-database cached tags into the tags tables" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    article = create_article
    Rails.cache.write("article_tags/#{article.id}", %w[ایران اقتصاد])

    assert_equal 1, TagGenerator.import_cached_tags!
    assert_equal %w[ایران اقتصاد], TagGenerator.tags_for(article.reload).last(2)
    assert_equal 0, TagGenerator.import_cached_tags!
  ensure
    Rails.cache = original
  end
end
