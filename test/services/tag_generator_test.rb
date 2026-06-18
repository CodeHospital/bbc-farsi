require "test_helper"

class TagGeneratorTest < ActiveSupport::TestCase
  test "process splits Persian comma/newline tag lists and caps the count" do
    tags = TagGenerator.process("tags" => "ایران، اقتصاد, تحریم\nانرژی")

    assert_equal %w[ایران اقتصاد تحریم انرژی], tags
  end

  test "process strips think blocks, hashes, blanks and duplicates" do
    raw = "<think>reasoning</think>#ایران, ایران, , اقتصاد"
    assert_equal %w[ایران اقتصاد], TagGenerator.process("tags" => raw)
  end

  test "requests builds a single keyed chat request from the translation text" do
    translation = create_translation(attrs: { translated_title: "عنوان", translated_body: "متن" })
    requests = TagGenerator.requests(translation)

    assert_equal 1, requests.size
    assert_equal "tags", requests.first[:key]
    assert_match "عنوان", requests.first[:messages].last[:content]
  end

  test "store and tags_for round-trip per article" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    article = create_article

    assert_empty TagGenerator.tags_for(article)
    refute TagGenerator.tagged?(article)

    TagGenerator.store(article.id, %w[ایران اقتصاد])

    assert TagGenerator.tagged?(article)
    assert_equal %w[ایران اقتصاد], TagGenerator.tags_for(article)
  ensure
    Rails.cache = original
  end

  test "untagged_candidates excludes already-tagged articles" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    tagged = create_translation(attrs: { translated_title: "دارای برچسب" })
    untagged = create_translation(attrs: { translated_title: "بدون برچسب" })
    TagGenerator.store(tagged.article_id, %w[برچسب])

    candidate_ids = TagGenerator.untagged_candidates.map(&:article_id)

    assert_includes candidate_ids, untagged.article_id
    refute_includes candidate_ids, tagged.article_id
  ensure
    Rails.cache = original
  end
end
