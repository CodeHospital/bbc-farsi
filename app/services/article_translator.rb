# Builds the LLM chat requests for translating a rewrite to Persian and
# post-processes the worker's responses. No longer calls Ollama directly.
class ArticleTranslator
  PROMPT_FILE = Rails.root.join("prompt").to_s

  def self.system_prompt = File.read(PROMPT_FILE)

  # Two requests — one for the title, one for the body — keyed so the worker's
  # responses can be mapped back to translation fields.
  def self.requests(rewrite)
    prompt = system_prompt
    [
      {
        key: "title",
        messages: [
          { role: "system", content: prompt },
          { role: "user",   content: (rewrite.rewritten_title.presence || rewrite.article.title).to_s }
        ]
      },
      {
        key: "body",
        messages: [
          { role: "system", content: prompt },
          { role: "user",   content: rewrite.content.to_s }
        ]
      }
    ]
  end

  def self.process(responses)
    {
      translated_title: responses["title"].to_s,
      translated_body:  responses["body"].to_s
    }
  end

  def self.debug_curl_title(rewrite, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: system_prompt,
      user_text:     (rewrite.rewritten_title.presence || rewrite.article.title).to_s,
      url:           server&.url
    )
  end

  def self.debug_curl_body(rewrite, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: system_prompt,
      user_text:     rewrite.content.to_s,
      url:           server&.url
    )
  end
end
