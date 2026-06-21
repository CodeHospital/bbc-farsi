# Builds the LLM chat requests for rewriting an article and post-processes the
# worker's response. No longer calls Ollama directly — the worker client does.
class ArticleRewriter
  SYSTEM_PROMPT = <<~PROMPT.strip
    You are a news editor. Given a BBC news article title and its summary, rewrite the body as a
    clear, self-contained paragraph in plain English. Expand any abbreviations, add brief factual
    context where helpful, and make it easy to understand for a general international audience, specially people with limited English proficiency. Do not assume the reader has any prior knowledge of the article's topic. Output only the rewritten body — no title, no punctuation at the end, no metadata, no commentary.
    Do not use any HTML tags or formatting.
  PROMPT

  TITLE_SYSTEM_PROMPT = <<~PROMPT.strip
    You are a news editor. Given a BBC news article title and its rewritten body, produce a concise,
    accurate headline for the article, so it's easy to understand for people with limited English proficiency. Output only the headline — no punctuation at the end, no
    metadata, no commentary.
  PROMPT

  # Chat requests stored on the Task and executed by the worker.
  # Each entry: { key:, messages: [{role:, content:}, ...] }
  # "body" is executed first; "title" references the body result via {{body}}.
  def self.requests(article)
    [
      {
        key: "body",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: "Title: #{article.title}\n\n#{article.description}" }
        ]
      },
      {
        key: "title",
        messages: [
          { role: "system", content: TITLE_SYSTEM_PROMPT },
          { role: "user",   content: "Original title: #{article.title}\n\nRewritten body: {{body}}" }
        ]
      }
    ]
  end

  # Turns the worker's responses ({ "body" => "...", "title" => "..." }) into
  # { rewritten_title:, content: }, stripping any Qwen3 <think> reasoning blocks.
  def self.process(responses)
    {
      rewritten_title: clean(responses["title"]),
      content:         clean(responses["body"])
    }
  end

  def self.debug_curl(article, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: SYSTEM_PROMPT,
      user_text:     "Title: #{article.title}\n\n#{article.description}",
      url:           server&.url
    )
  end

  def self.clean(text)
    text.to_s.gsub(%r{<think>.*?</think>}m, "").strip
  end
  private_class_method :clean
end
