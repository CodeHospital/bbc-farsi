# Classifies the ORIGINAL (English) article before/alongside its rewrite:
#
#   * political leaning — left / center / right split, summing to 100
#   * nature — factual (things that already happened) / speculative
#     (predictions or speculation about the future), summing to 100
#   * a short reasoning sentence, in English ("reasoning") and Persian
#     ("farsi_reasoning")
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
    SentryBreadcrumb.record("ArticleAnalyzer.process", category: "article_analyzer", data: { responses: responses })
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
      analysis_reasoning:    parsed["reasoning"].to_s.strip.presence,
      analysis_reasoning_fa: parsed["farsi_reasoning"].to_s.strip.presence,
      analysis_status:       "completed",
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
    SentryBreadcrumb.record("ArticleAnalyzer.parse_json raw_response=#{raw_response}", category: "article_analyzer", data: { raw_response: raw_response })
    text      = LlmText.clean(raw_response.to_s)
    json_text = text[/\{.*\}/m]
    raise ArgumentError, "analysis response contained no JSON object: #{text.truncate(200)}" unless json_text

    SentryBreadcrumb.record("ArticleAnalyzer.parse_json: extracted JSON", category: "article_analyzer", data: { json_text: json_text })

    parse_json_object(json_text)
  end

  NUMERIC_FIELDS = %w[left center right factual speculative].freeze
  TEXT_FIELDS    = %w[reasoning farsi_reasoning].freeze

  # Strict parse first. When the model's JSON is malformed (trailing commas,
  # unquoted keys, unescaped quotes inside a string, stray markdown, ...) escape
  # the inner quotes and fall back to json-repair. If even that fails (e.g. the
  # model appended a broken extra key with no value), pull the known fields
  # out one by one before giving up.
  def self.parse_json_object(json_text)
    parsed_object =
      begin
        JSON.parse(json_text)
      rescue JSON::ParserError
        escaped_json_text = escape_inner_quotes(json_text)
        begin
          JSON.repair(escaped_json_text, return_objects: true)
        rescue JSON::JSONRepairError => repair_error
          extract_known_fields(escaped_json_text) ||
            raise(ArgumentError, "analysis response was not valid JSON: #{repair_error.message}")
        end
      end

    raise ArgumentError, "analysis response was not a JSON object: #{json_text.truncate(200)}" unless parsed_object.is_a?(Hash)

    parsed_object
  end

  # Last-resort field-by-field extraction from text whose inner quotes are
  # already escaped. Returns nil when none of the numeric fields is present.
  def self.extract_known_fields(escaped_json_text)
    extracted_fields = {}
    NUMERIC_FIELDS.each do |field_name|
      number_match = escaped_json_text.match(/"#{field_name}"\s*:\s*"?(-?\d+(?:\.\d+)?)/)
      extracted_fields[field_name] = number_match[1].to_f if number_match
    end
    return nil if extracted_fields.empty?

    TEXT_FIELDS.each do |field_name|
      text_match = escaped_json_text.match(/"#{field_name}"\s*:\s*("(?:\\.|[^"\\])*")/m)
      next unless text_match

      extracted_fields[field_name] =
        begin
          JSON.parse(text_match[1])
        rescue JSON::ParserError
          text_match[1][1..-2]
        end
    end

    SentryBreadcrumb.record("ArticleAnalyzer.extract_known_fields", category: "article_analyzer", data: { extracted_fields: extracted_fields })
    extracted_fields
  end

  # Escapes double quotes that sit inside a string value, e.g. the ("Selenskyj")
  # in a reasoning sentence. A quote only closes a string when the next
  # non-space character is , } ] or : (or the text ends); any other quote is
  # content and gets a backslash.
  def self.escape_inner_quotes(json_text)
    characters        = json_text.chars
    escaped_text      = +""
    inside_string     = false
    character_index   = 0

    while character_index < characters.length
      character = characters[character_index]

      if inside_string && character == "\\"
        escaped_text << character << characters[character_index + 1].to_s
        character_index += 2
        next
      end

      if character == '"'
        if !inside_string
          inside_string = true
        elsif closes_json_string?(characters, character_index + 1)
          inside_string = false
        else
          character = '\\"'
        end
      end

      escaped_text << character
      character_index += 1
    end

    escaped_text
  end

  def self.closes_json_string?(characters, following_index)
    next_index = following_index
    next_index += 1 while next_index < characters.length && characters[next_index].match?(/\s/)
    next_index >= characters.length || [ ",", "}", "]", ":" ].include?(characters[next_index])
  end

  # Clamps each value to 0..100 and rescales so the parts sum to 100; the
  # rounding remainder goes to the largest part. All-zero/missing → fallback.
  def self.normalize_split(raw_values, fallback:)
    values = raw_values.map { |value| value.respond_to?(:to_f) ? value.to_f.clamp(0, 100) : 0.0 }
    total  = values.sum
    return fallback if total.zero?

    scaled = values.map { |value| (value * 100 / total).round }
    scaled[scaled.index(scaled.max)] += 100 - scaled.sum
    scaled
  end

  private_class_method :parse_json, :parse_json_object, :extract_known_fields, :normalize_split, :current_prompt_version
end
