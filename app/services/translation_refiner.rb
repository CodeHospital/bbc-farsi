# Builds the LLM chat requests for refining an existing Persian translation and
# post-processes the worker's responses. No longer calls Ollama directly.
# Prompt text is DB-backed (see Prompt) so admins/editors can edit it; each
# request always uses the current version, and embeds its prompt_version_id
# so Task can record which version produced the result.
class TranslationRefiner
  # `translation` is the SOURCE translation whose text is being refined.
  def self.requests(translation)
    title_version = Prompt.current_version("refine_title")
    body_version  = Prompt.current_version("refine_body")

    [
      {
        key: "title",
        prompt_version_id: title_version.id,
        messages: [
          { role: "system", content: title_version.content },
          { role: "user",   content: "Title: #{translation.translated_title}\n\nBody: #{translation.translated_body}" }
        ]
      },
      {
        key: "body",
        prompt_version_id: body_version.id,
        messages: [
          { role: "system", content: body_version.content },
          { role: "user",   content: "Title: #{translation.translated_title}\n\nBody: #{translation.translated_body}" }
        ]
      }
    ]
  end

  def self.process(responses)
    {
      translated_title: strip_think(responses["title"]),
      translated_body:  strip_think(responses["body"])
    }
  end

  def self.strip_think(text)
    text.to_s.gsub(%r{<think>.*?</think>}m, "").strip
  end

  def self.debug_curl_title(translation, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: Prompt.content_for("refine_title"),
      user_text:     "Title: #{translation.translated_title}\n\nBody: #{translation.translated_body}",
      url:           server&.url
    )
  end

  def self.debug_curl_body(translation, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: Prompt.content_for("refine_body"),
      user_text:     "Title: #{translation.translated_title}\n\nBody: #{translation.translated_body}",
      url:           server&.url
    )
  end
end
