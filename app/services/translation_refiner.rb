# Builds the LLM chat requests for refining an existing Persian translation and
# post-processes the worker's responses. No longer calls Ollama directly.
class TranslationRefiner
  TITLE_PROMPT = <<~PROMPT.strip
    You are a professional Persian (Farsi) news editor refining a news headline.
    Improve the headline for clarity, naturalness, and conciseness. Keep it as a
    single short headline — do not add a body, explanation, or extra sentences.
    Output only the refined Persian headline — no commentary, no labels.
  PROMPT

  BODY_PROMPT = <<~PROMPT.strip
    You are a professional Persian (Farsi) news editor refining the body of a news article.
    Improve the text for clarity, naturalness, and readability. Fix any awkward phrasing,
    improve vocabulary, and ensure it reads like professionally written Persian journalism.
    Output only the refined Persian body text — no title, no commentary, no explanations.
  PROMPT

  # `translation` is the SOURCE translation whose text is being refined.
  def self.requests(translation)
    [
      {
        key: "title",
        messages: [
          { role: "system", content: TITLE_PROMPT },
          { role: "user",   content: translation.translated_title.to_s }
        ]
      },
      {
        key: "body",
        messages: [
          { role: "system", content: BODY_PROMPT },
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
      system_prompt: TITLE_PROMPT,
      user_text:     translation.translated_title.to_s,
      url:           server&.url
    )
  end

  def self.debug_curl_body(translation, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: BODY_PROMPT,
      user_text:     translation.translated_body.to_s,
      url:           server&.url
    )
  end
end
