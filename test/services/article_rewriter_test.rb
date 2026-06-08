require "test_helper"

class ArticleRewriterTest < ActiveSupport::TestCase
  setup do
    @article = Article.new(title: "UK floods worsen", description: "Heavy rain causes flooding.")
  end

  test "builds a single content request with system + user messages" do
    requests = ArticleRewriter.requests(@article)

    assert_equal 1, requests.size
    request = requests.first
    assert_equal "content", request[:key]
    assert_equal "system", request[:messages][0][:role]
    assert_includes request[:messages][0][:content], "news editor"
    assert_equal "user", request[:messages][1][:role]
    assert_includes request[:messages][1][:content], "UK floods worsen"
    assert_includes request[:messages][1][:content], "Heavy rain causes flooding."
  end

  test "process returns the content response verbatim when clean" do
    assert_equal "Rewritten body text.", ArticleRewriter.process("content" => "Rewritten body text.")
  end

  test "process strips a Qwen3 <think> reasoning block" do
    raw = "<think>some internal reasoning\nthat spans lines</think>The actual rewrite."
    result = ArticleRewriter.process("content" => raw)
    assert_equal "The actual rewrite.", result
    assert_not_includes result, "<think>"
  end

  test "process strips multiple <think> blocks" do
    raw = "<think>block1</think>First part.<think>block2</think>Second part."
    assert_equal "First part.Second part.", ArticleRewriter.process("content" => raw)
  end

  test "process strips <think> block with surrounding whitespace" do
    raw = "<think>reasoning</think>   Clean output.   "
    assert_equal "Clean output.", ArticleRewriter.process("content" => raw)
  end
end
