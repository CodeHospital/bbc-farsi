# Builds the LLM chat requests for refining an existing Persian translation and
# post-processes the worker's responses. No longer calls Ollama directly.
class TranslationRefiner
  SYSTEM_PROMPT = <<~PROMPT.strip
    You are a professional Persian (Farsi) news editor. Improve the following Persian news text for
    clarity, naturalness, and readability. Fix any awkward phrasing, improve vocabulary, and ensure
    it reads like professionally written Persian journalism.
    Output only the improved Persian text — no commentary, no explanations.
  PROMPT

  # `translation` is the SOURCE translation whose text is being refined.
  def self.requests(translation)
    [
      {
        key: "title",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: translation.translated_title.to_s }
        ]
      },
      {
        key: "body",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: translation.translated_body.to_s }
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
      system_prompt: SYSTEM_PROMPT,
      user_text:     translation.translated_title.to_s,
      url:           server&.url
    )
  end

  def self.debug_curl_body(translation, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: SYSTEM_PROMPT,
      user_text:     translation.translated_body.to_s,
      url:           server&.url
    )
  end
end
