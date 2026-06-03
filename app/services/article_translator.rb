class ArticleTranslator
  PROMPT_FILE = Rails.root.join("prompt").to_s

  def self.debug_curl_title(rewrite, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: File.read(PROMPT_FILE),
      user_text:     rewrite.article.title,
      url:           server&.url
    )
  end

  def self.debug_curl_body(rewrite, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: File.read(PROMPT_FILE),
      user_text:     rewrite.content.to_s,
      url:           server&.url
    )
  end

  def initialize(server: nil)
    @ollama        = OllamaClient.new(url: server&.url)
    @system_prompt = File.read(PROMPT_FILE)
  end

  def translate(rewrite, model:)
    translated_title = @ollama.chat(
      model:,
      system_prompt: @system_prompt,
      user_text: rewrite.article.title
    )
    translated_body = @ollama.chat(
      model:,
      system_prompt: @system_prompt,
      user_text: rewrite.content.to_s
    )
    { translated_title:, translated_body: }
  end
end
