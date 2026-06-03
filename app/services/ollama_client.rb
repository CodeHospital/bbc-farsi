class OllamaClient
  DEFAULT_URL = "http://localhost:11434"

  def self.curl_command(model:, system_prompt:, user_text:, url: nil)
    ollama_url = url || ENV.fetch("OLLAMA_URL", DEFAULT_URL)
    payload = JSON.pretty_generate(
      model:    model,
      stream:   false,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user",   content: user_text }
      ]
    )
    <<~SHELL.strip
      curl #{ollama_url}/api/chat \\
        -H 'Content-Type: application/json' \\
        -d @- << 'PAYLOAD'
      #{payload}
      PAYLOAD
    SHELL
  end

  def initialize(url: nil)
    resolved_url = url || ENV.fetch("OLLAMA_URL", DEFAULT_URL)
    @client = Ollama.new(
      credentials: { address: resolved_url },
      options: { server_sent_events: true }
    )
  end

  def chat(model:, system_prompt:, user_text:)
    response = @client.chat(
      {
        model:,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user",   content: user_text }
        ],
        stream: false
      }
    )
    response.last.dig("message", "content").to_s
  end
end
