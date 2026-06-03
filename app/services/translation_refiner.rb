class TranslationRefiner
  SYSTEM_PROMPT = <<~PROMPT.strip
    You are a professional Persian (Farsi) news editor. Improve the following Persian news text for
    clarity, naturalness, and readability. Fix any awkward phrasing, improve vocabulary, and ensure
    it reads like professionally written Persian journalism.
    Output only the improved Persian text — no commentary, no explanations.
  PROMPT

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

  def initialize(server: nil)
    @ollama = OllamaClient.new(url: server&.url)
  end

  def refine(translation, model:)
    refined_title = @ollama.chat(
      model:,
      system_prompt: SYSTEM_PROMPT,
      user_text: translation.translated_title.to_s
    ).gsub(%r{<think>.*?</think>}m, "").strip

    refined_body = @ollama.chat(
      model:,
      system_prompt: SYSTEM_PROMPT,
      user_text: translation.translated_body.to_s
    ).gsub(%r{<think>.*?</think>}m, "").strip

    { translated_title: refined_title, translated_body: refined_body }
  end
end
