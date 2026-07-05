# Builds the LLM chat requests for rewriting an article and post-processes the
# worker's response. No longer calls Ollama directly — the worker client does.
# Prompt text is DB-backed (see Prompt) so admins/editors can edit it; each
# request always uses the current version, and embeds its prompt_version_id
# so Task can record which version produced the result.
class ArticleRewriter
  # Chat requests stored on the Task and executed by the worker.
  # Each entry: { key:, prompt_version_id:, messages: [{role:, content:}, ...] }
  # "body" is executed first; "title" references the body result via {{body}}.
  def self.requests(article)
    body_version  = Prompt.current_version("rewrite_body")
    title_version = Prompt.current_version("rewrite_title")

    [
      {
        key: "body",
        prompt_version_id: body_version.id,
        messages: [
          { role: "system", content: body_version.content },
          { role: "user",   content: "Title: #{article.title}\n\n#{article.description}" }
        ]
      },
      {
        key: "title",
        prompt_version_id: title_version.id,
        messages: [
          { role: "system", content: title_version.content },
          { role: "user",   content: "Original title: #{article.title}\n\nRewritten body: {{body}}" }
        ]
      }
    ]
  end

  # Turns the worker's responses ({ "body" => "...", "title" => "..." }) into
  # { rewritten_title:, content: }, stripping any Qwen3 <think> reasoning blocks.
  def self.process(responses)
    {
      rewritten_title: clean(responses["title"]),
      content:         clean(responses["body"])
    }
  end

  def self.debug_curl(article, server: nil, model:)
    OllamaClient.curl_command(
      model:,
      system_prompt: Prompt.content_for("rewrite_body"),
      user_text:     "Title: #{article.title}\n\n#{article.description}",
      url:           server&.url
    )
  end

  def self.clean(text)
    text.to_s.gsub(%r{<think>.*?</think>}m, "").strip
  end
  private_class_method :clean
end
