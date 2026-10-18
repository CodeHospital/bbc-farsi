require "test_helper"

class SkipPhraseTest < ActiveSupport::TestCase
  test "strips whitespace and rejects duplicates per field, ignoring case" do
    SkipPhrase.create!(phrase: "  Live blog ", match_field: "title")
    assert_equal "Live blog", SkipPhrase.find_by(match_field: "title", phrase: "Live blog").phrase
    assert_not SkipPhrase.new(phrase: "live BLOG", match_field: "title").valid?
    assert SkipPhrase.new(phrase: "live blog", match_field: "url").valid?
  end

  test "rejects blank phrases and unknown fields" do
    assert_not SkipPhrase.new(phrase: " ", match_field: "title").valid?
    assert_not SkipPhrase.new(phrase: "x", match_field: "body").valid?
  end

  test "Article.ignore_reason uses admin-added phrases, case-insensitively" do
    SkipPhrase.create!(phrase: "live blog", match_field: "title")
    SkipPhrase.create!(phrase: "/sport/", match_field: "url")

    assert_match(/skip phrase "live blog"/, Article.ignore_reason("Ukraine LIVE BLOG day 3", "https://bbc.co.uk/news/a"))
    assert_match(/skip phrase "\/sport\/"/, Article.ignore_reason("Fine", "https://bbc.co.uk/sport/football/1"))
    assert_nil Article.ignore_reason("Fine", "https://bbc.co.uk/news/a")
  end

  test "disabled and deleted phrases no longer skip" do
    phrase = SkipPhrase.create!(phrase: "live blog", match_field: "title")
    phrase.update!(enabled: false)
    assert_not Article.ignorable?("Live blog", "https://bbc.co.uk/news/a")

    phrase.update!(enabled: true)
    assert Article.ignorable?("Live blog", "https://bbc.co.uk/news/a")
    phrase.destroy!
    assert_not Article.ignorable?("Live blog", "https://bbc.co.uk/news/a")
  end
end
