class ArticleRewriter
  SYSTEM_PROMPT = <<~PROMPT.strip
    You are a news editor. Given a BBC news article title and its summary, rewrite the body as a
    clear, self-contained paragraph in plain English. Expand any abbreviations, add brief factual
    context where helpful, and make it easy to understand for a general international audience.
    Output only the rewritten article text — no headings, no metadata, no commentary.
  PROMPT

  def self.debug_curl(article, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: SYSTEM_PROMPT,
      user_text:     "Title: #{article.title}\n\n#{article.description}",
      url:           server&.url
    )
  end

  def initialize(server: nil)
    @ollama = OllamaClient.new(url: server&.url)
  end

  def rewrite(article, model:)
    user_text = "Title: #{article.title}\n\n#{article.description}"
    @ollama.chat(model:, system_prompt: SYSTEM_PROMPT, user_text:)
           .gsub(%r{<think>.*?</think>}m, "")
           .strip
  end
end
