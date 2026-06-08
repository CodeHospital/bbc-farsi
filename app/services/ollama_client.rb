# Builds a copy-pasteable `curl` command for the admin "debug" panels so an
# operator can reproduce an LLM call by hand. The Rails app no longer talks to
# Ollama itself — the separate worker client does (see worker/worker.rb).
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
end
