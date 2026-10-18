require "test_helper"

class TextDiffTest < ActiveSupport::TestCase
  test "marks a replaced word as delete + insert and keeps the rest equal" do
    diff_operations = TextDiff.word_diff("the quick fox", "the slow fox")
    assert_equal [ [ :equal, "the " ], [ :delete, "quick" ], [ :insert, "slow" ], [ :equal, " fox" ] ], diff_operations
  end

  test "pieces reassemble into the old and new texts" do
    old_text = "خبر فوری از تهران امروز"
    new_text = "خبر مهم از تهران و اصفهان امروز"
    diff_operations = TextDiff.word_diff(old_text, new_text)

    assert_equal old_text, diff_operations.reject { |operation, _| operation == :insert }.map(&:last).join
    assert_equal new_text, diff_operations.reject { |operation, _| operation == :delete }.map(&:last).join
  end

  test "handles nil and empty input" do
    assert_equal [], TextDiff.word_diff(nil, "")
    assert_equal [ [ :insert, "new" ] ], TextDiff.word_diff(nil, "new")
    assert_equal [ [ :delete, "old" ] ], TextDiff.word_diff("old", nil)
  end

  test "falls back to whole-text replacement for very large texts" do
    old_text = ([ "a" ] * 2_500).join(" ")
    new_text = ([ "b" ] * 2_500).join(" ")
    assert_equal [ [ :delete, old_text ], [ :insert, new_text ] ], TextDiff.word_diff(old_text, new_text)
  end
end
