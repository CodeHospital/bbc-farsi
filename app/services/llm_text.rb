# Shared post-processing for raw LLM output: strips <think>...</think>
# reasoning blocks (emitted by reasoning models like the qwen3 family) plus
# surrounding whitespace. Used by every service that turns worker responses
# into stored content, so a reasoning model configured for any pipeline stage
# never leaks its chain-of-thought onto the portal or Telegram (previously
# ArticleRewriter and TranslationRefiner each had their own copy of this
# regex, and ArticleTranslator had none at all — see plan2.md H-9).
module LlmText
  def self.clean(text)
    text.to_s.gsub(%r{<think>.*?</think>}m, "").strip
  end
end
