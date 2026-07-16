# Builds the LLM chat requests for translating a rewrite to Persian and
# post-processes the worker's responses. No longer calls Ollama directly.
# Prompt text is DB-backed (see Prompt) so admins/editors can edit it; each
# request always uses the current version, and embeds its prompt_version_id
# so Task can record which version produced the result.
class ArticleTranslator
  # Two requests — one for the title, one for the body — keyed so the worker's
  # responses can be mapped back to translation fields.
  def self.requests(rewrite)
    version = Prompt.current_version("translate")
    [
      {
        key: "title",
        prompt_version_id: version.id,
        messages: [
          { role: "system", content: version.content },
          { role: "user",   content: (rewrite.rewritten_title.presence || rewrite.article.title).to_s }
        ]
      },
      {
        key: "body",
        prompt_version_id: version.id,
        messages: [
          { role: "system", content: version.content },
          { role: "user",   content: rewrite.content.to_s }
        ]
      }
    ]
  end

  def self.process(responses)
    {
      translated_title: LlmText.clean(responses["title"]),
      translated_body:  LlmText.clean(responses["body"])
    }
  end

  def self.debug_curl_title(rewrite, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: Prompt.content_for("translate"),
      user_text:     (rewrite.rewritten_title.presence || rewrite.article.title).to_s,
      url:           server&.url
    )
  end

  def self.debug_curl_body(rewrite, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: Prompt.content_for("translate"),
      user_text:     rewrite.content.to_s,
      url:           server&.url
    )
  end
end
