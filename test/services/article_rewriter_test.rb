require "test_helper"

class ArticleRewriterTest < ActiveSupport::TestCase
  setup do
    @article = Article.new(title: "UK floods worsen", description: "Heavy rain causes flooding.")
  end

  test "returns rewritten content from Ollama" do
    fake_ollama = fake_client_returning("Rewritten body text.")
    OllamaClient.stub(:new, fake_ollama) do
      assert_equal "Rewritten body text.", ArticleRewriter.new.rewrite(@article)
    end
  end

  test "strips Qwen3 <think> reasoning block from output" do
    raw = "<think>some internal reasoning\nthat spans lines</think>The actual rewrite."
    OllamaClient.stub(:new, fake_client_returning(raw)) do
      result = ArticleRewriter.new.rewrite(@article)
      assert_equal "The actual rewrite.", result
      assert_not_includes result, "<think>"
    end
  end

  test "strips multiple <think> blocks" do
    raw = "<think>block1</think>First part.<think>block2</think>Second part."
    OllamaClient.stub(:new, fake_client_returning(raw)) do
      assert_equal "First part.Second part.", ArticleRewriter.new.rewrite(@article)
    end
  end

  test "strips <think> block with trailing whitespace" do
    raw = "<think>reasoning</think>   Clean output.   "
    OllamaClient.stub(:new, fake_client_returning(raw)) do
      assert_equal "Clean output.", ArticleRewriter.new.rewrite(@article)
    end
  end

  private

  # Returns a fake OllamaClient instance whose #chat always returns `response`
  def fake_client_returning(response)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| response }
    client
  end
end
