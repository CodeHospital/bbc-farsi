# Builds the LLM chat requests for rewriting an article and post-processes the
# worker's response. No longer calls Ollama directly — the worker client does.
class ArticleRewriter
  SYSTEM_PROMPT = <<~PROMPT.strip
    You are a news editor. Given a BBC news article title and its summary, rewrite the body as a
    clear, self-contained paragraph in plain English. Expand any abbreviations, add brief factual
    context where helpful, and make it easy to understand for a general international audience.
    Output only the rewritten article text — no headings, no metadata, no commentary. rewrite the title using the body as context, but do not include the body in the title. Do not use any HTML tags or formatting.
  PROMPT

  # Chat requests stored on the Task and executed by the worker.
  # Each entry: { key:, messages: [{role:, content:}, ...] }
  def self.requests(article)
    [
      {
        key: "content",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: "Title: #{article.title}\n\n#{article.description}" }
        ]
      }
    ]
  end

  # Turns the worker's responses ({ "content" => "..." }) into the rewrite body,
  # stripping any Qwen3 <think> reasoning block.
  def self.process(responses)
    responses["content"].to_s.gsub(%r{<think>.*?</think>}m, "").strip
  end

  def self.debug_curl(article, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: SYSTEM_PROMPT,
      user_text:     "Title: #{article.title}\n\n#{article.description}",
      url:           server&.url
    )
  end
end
