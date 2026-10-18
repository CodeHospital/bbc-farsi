# Classifies the ORIGINAL (English) article before/alongside its rewrite:
#
#   * political leaning — left / center / right split, summing to 100
#   * nature — factual (things that already happened) / speculative
#     (predictions or speculation about the future), summing to 100
#   * a short reasoning sentence
#
# Runs through the worker queue as an `analyze` Task whose target is the
# Article itself (read-only for the task lifecycle — the article's pipeline
# `status` is never touched). Results are stored on the article's analysis
# columns, which admins can edit afterwards. Display only: nothing in the
# pipeline or autopost depends on these values.
class ArticleAnalyzer
  PROMPT_KEY = "analyze".freeze

  # Prompt text is DB-backed (see Prompt) so admins/editors can edit it; the
  # request always uses the current version, and embeds its prompt_version_id
  # so Task can record which version produced the result.
  def self.requests(article)
    version = current_prompt_version
    [
      {
        key: "analysis",
        prompt_version_id: version.id,
        messages: [
          { role: "system", content: version.content },
          { role: "user",   content: "Title: #{article.title}\n\nDescription: #{article.description}" }
        ]
      }
    ]
  end

  # Turns the worker's JSON response into article attributes. Each split is
  # clamped and normalized to sum to exactly 100, so a sloppy model answer
  # (e.g. 40/40/40) still produces consistent percentages.
  def self.process(responses)
    parsed = parse_json(responses["analysis"])

    bias_left, bias_center, bias_right =
      normalize_split([ parsed["left"], parsed["center"], parsed["right"] ], fallback: [ 0, 100, 0 ])
    factual, speculative =
      normalize_split([ parsed["factual"], parsed["speculative"] ], fallback: [ 100, 0 ])

    {
      bias_left_percent:   bias_left,
      bias_center_percent: bias_center,
      bias_right_percent:  bias_right,
      factual_percent:     factual,
      speculative_percent: speculative,
      analysis_reasoning:  parsed["reasoning"].to_s.strip.presence,
      analysis_status:     "completed",
      analyzed_at:         Time.current
    }
  end

  # Not-archived articles that were never analyzed (or whose analysis failed)
  # — the work `bbc:analyze` and the admin "Analyze missing" button enqueue.
  def self.unanalyzed_candidates
    Article.not_archived.where(analysis_status: [ nil, "failed" ])
  end

  # Existing databases predate the "analyze" prompt; seed it on first use
  # (seed_defaults! is idempotent and never overwrites edited prompts).
  def self.current_prompt_version
    Prompt.seed_defaults! unless Prompt.exists?(key: PROMPT_KEY)
    Prompt.current_version(PROMPT_KEY)
  end

  def self.parse_json(raw_response)
    text      = LlmText.clean(raw_response.to_s)
    json_text = text[/\{.*\}/m]
    raise ArgumentError, "analysis response contained no JSON object: #{text.truncate(200)}" unless json_text

    JSON.parse(json_text)
  rescue JSON::ParserError => e
    raise ArgumentError, "analysis response was not valid JSON: #{e.message}"
  end

  # Clamps each value to 0..100 and rescales so the parts sum to 100; the
  # rounding remainder goes to the largest part. All-zero/missing → fallback.
  def self.normalize_split(raw_values, fallback:)
    values = raw_values.map { |value| value.to_f.clamp(0, 100) }
    total  = values.sum
    return fallback if total.zero?

    scaled = values.map { |value| (value * 100 / total).round }
    scaled[scaled.index(scaled.max)] += 100 - scaled.sum
    scaled
  end

  private_class_method :parse_json, :normalize_split, :current_prompt_version
end
