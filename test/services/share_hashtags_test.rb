require "test_helper"

class ShareHashtagsTest < ActiveSupport::TestCase
  test "publisher and Persian country hashtags for a BBC feed" do
    article = Article.new(feed: Feed.new(name: "World", source: "bbc"))
    assert_equal "#BBC_News #انگلیس", ShareHashtags.for(article)
  end

  test "English country name for the English edition" do
    article = Article.new(feed: Feed.new(name: "World", source: "nyt"))
    assert_equal "#The_New_York_Times #United_States", ShareHashtags.for(article, lang: "en")
  end

  test "multi-word and punctuated publisher names become a single hashtag" do
    assert_equal "#heise_online", ShareHashtags.hashtag("heise online")
    assert_equal "#Ad_Hoc_News", ShareHashtags.hashtag("Ad Hoc News")
    assert_equal "#T_Online", ShareHashtags.hashtag("T-Online.")
    assert_nil ShareHashtags.hashtag(" — ")
  end

  test "Persian zero-width non-joiner is kept inside a hashtag" do
    assert_equal "#بی‌بی‌سی", ShareHashtags.hashtag("بی‌بی‌سی")
  end

  test "blank without a feed, and append_to leaves the title alone" do
    article = Article.new
    assert_equal "", ShareHashtags.for(article)
    assert_equal "عنوان", ShareHashtags.append_to("عنوان", article)
  end

  test "append_to adds hashtags after the title" do
    article = Article.new(feed: Feed.new(name: "Tech", source: "heise"))
    assert_equal "عنوان #heise_online #آلمان", ShareHashtags.append_to("عنوان", article)
  end
end
