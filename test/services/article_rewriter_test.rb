require "test_helper"

class ArticleRewriterTest < ActiveSupport::TestCase
  setup do
    @article = Article.new(title: "UK floods worsen", description: "Heavy rain causes flooding.")
  end

  test "builds two requests: body first, then title" do
    requests = ArticleRewriter.requests(@article)

    assert_equal 2, requests.size

    body_req = requests[0]
    assert_equal "body", body_req[:key]
    assert_equal "system", body_req[:messages][0][:role]
    assert_includes body_req[:messages][0][:content], "news editor"
    assert_equal "user", body_req[:messages][1][:role]
    assert_includes body_req[:messages][1][:content], "UK floods worsen"
    assert_includes body_req[:messages][1][:content], "Heavy rain causes flooding."

    title_req = requests[1]
    assert_equal "title", title_req[:key]
    assert_includes title_req[:messages][1][:content], "{{body}}"
    assert_includes title_req[:messages][1][:content], "UK floods worsen"
  end

  test "process returns rewritten_title and content from separate responses" do
    result = ArticleRewriter.process("title" => "New Headline", "body" => "Rewritten body text.")
    assert_equal({ rewritten_title: "New Headline", content: "Rewritten body text." }, result)
  end

  test "process strips Qwen3 <think> blocks from both fields" do
    result = ArticleRewriter.process(
      "title" => "<think>thinking</think>Clean Headline",
      "body"  => "<think>some internal reasoning\nthat spans lines</think>The actual rewrite."
    )
    assert_equal "Clean Headline", result[:rewritten_title]
    assert_equal "The actual rewrite.", result[:content]
  end

  test "process strips multiple <think> blocks from body" do
    result = ArticleRewriter.process(
      "title" => "Headline",
      "body"  => "<think>block1</think>First part.<think>block2</think>Second part."
    )
    assert_equal "First part.Second part.", result[:content]
  end

  test "process strips <think> block with surrounding whitespace" do
    result = ArticleRewriter.process(
      "title" => "  Headline  ",
      "body"  => "<think>reasoning</think>   Clean output.   "
    )
    assert_equal "Headline", result[:rewritten_title]
    assert_equal "Clean output.", result[:content]
  end
end
