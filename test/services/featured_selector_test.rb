require "test_helper"

class FeaturedSelectorTest < ActiveSupport::TestCase
  # Swap in a real cache so the AI-selection round-trip can be exercised
  # (the test env default is :null_store).
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  def story(category:, title: "x", published_at: Time.current)
    feed = create_feed(category:)
    article = create_article(feed:, attrs: { published_at: })
    create_translation(rewrite: create_rewrite(article:), attrs: { translated_title: title })
  end

  test "heuristic prefers high-impact categories" do
    health = story(category: "health", title: "سلامت")
    top    = story(category: "top", title: "مهم")

    featured, rest = FeaturedSelector.select([ health, top ], limit: 1)

    assert_equal [ top ], featured
    assert_equal [ health ], rest
  end

  test "cached AI selection takes precedence over the heuristic" do
    with_memory_cache do
      top    = story(category: "top", title: "مهم")
      health = story(category: "health", title: "سلامت")

      FeaturedSelector.store([ health.article_id ])
      featured, rest = FeaturedSelector.select([ top, health ], limit: 1)

      assert_equal [ health ], featured
      assert_equal [ top ], rest
    end
  end

  test "process extracts article ids from the worker response" do
    assert_equal [ 12, 7, 30 ], FeaturedSelector.process("featured" => "ids: 12, 7 and 30")
  end

  test "requests builds a single keyed chat request listing candidate ids" do
    candidate = story(category: "world", title: "جهان")
    requests = FeaturedSelector.requests([ candidate ], limit: 2)

    assert_equal 1, requests.size
    assert_equal "featured", requests.first[:key]
    assert_match "ID #{candidate.article_id}: جهان", requests.first[:messages].last[:content]
  end
end
