require "test_helper"

class ArticleAnalyzerTest < ActiveSupport::TestCase
  test "requests send the original title and description with the analyze prompt" do
    article  = create_article(attrs: { title: "Original title", description: "Original summary" })
    requests = ArticleAnalyzer.requests(article)

    assert_equal [ "analysis" ], requests.map { |request| request[:key] }
    assert_equal Prompt.content_for("analyze"), requests.first[:messages].first[:content]
    assert_includes requests.first[:messages].last[:content], "Original title"
    assert_includes requests.first[:messages].last[:content], "Original summary"
  end

  test "requests seed the analyze prompt when an existing database lacks it" do
    analyze_prompt = Prompt.find_by!(key: "analyze")
    analyze_prompt.update!(current_prompt_version: nil)
    analyze_prompt.destroy!

    ArticleAnalyzer.requests(create_article)
    assert Prompt.exists?(key: "analyze")
  end

  test "process parses JSON wrapped in prose and code fences" do
    raw = "Sure!\n```json\n{\"left\": 10, \"center\": 60, \"right\": 30, \"factual\": 40, \"speculative\": 60, \"reasoning\": \"Forecast piece.\"}\n```"
    result = ArticleAnalyzer.process("analysis" => raw)

    assert_equal [ 10, 60, 30 ], result.values_at(:bias_left_percent, :bias_center_percent, :bias_right_percent)
    assert_equal [ 40, 60 ], result.values_at(:factual_percent, :speculative_percent)
    assert_equal "Forecast piece.", result[:analysis_reasoning]
    assert_equal "completed", result[:analysis_status]
  end

  test "process normalizes splits that do not add up to 100" do
    result = ArticleAnalyzer.process("analysis" => '{"left": 40, "center": 40, "right": 40, "factual": 3, "speculative": 1}')

    assert_equal 100, result.values_at(:bias_left_percent, :bias_center_percent, :bias_right_percent).sum
    assert_equal [ 75, 25 ], result.values_at(:factual_percent, :speculative_percent)
  end

  test "process falls back to center / factual when a split is missing" do
    result = ArticleAnalyzer.process("analysis" => '{"reasoning": "n/a"}')

    assert_equal [ 0, 100, 0 ], result.values_at(:bias_left_percent, :bias_center_percent, :bias_right_percent)
    assert_equal [ 100, 0 ], result.values_at(:factual_percent, :speculative_percent)
  end

  test "process repairs malformed JSON with json-repair (trailing comma, unquoted keys)" do
    raw = "{left: 10, center: 60, right: 30, factual: 40, speculative: 60, reasoning: \"Forecast piece.\",}"
    result = ArticleAnalyzer.process("analysis" => raw)

    assert_equal [ 10, 60, 30 ], result.values_at(:bias_left_percent, :bias_center_percent, :bias_right_percent)
    assert_equal [ 40, 60 ], result.values_at(:factual_percent, :speculative_percent)
    assert_equal "Forecast piece.", result[:analysis_reasoning]
  end

  test "process repairs unescaped quotes inside a reasoning string" do
    raw = '{"left": 20, "center": 65, "right": 15, "factual": 95, "speculative": 5, "reasoning": "While mentioning Ukraine\'s involvement ("Selenskyj"), the framing leans slightly left."}'
    result = ArticleAnalyzer.process("analysis" => raw)

    assert_equal [ 20, 65, 15 ], result.values_at(:bias_left_percent, :bias_center_percent, :bias_right_percent)
    assert_equal [ 95, 5 ], result.values_at(:factual_percent, :speculative_percent)
    assert_equal 'While mentioning Ukraine\'s involvement ("Selenskyj"), the framing leans slightly left.', result[:analysis_reasoning]
  end

  test "escape_inner_quotes leaves valid JSON unchanged" do
    valid_json = '{"reasoning": "He said \"hi\" twice", "left": 10}'

    assert_equal valid_json, ArticleAnalyzer.escape_inner_quotes(valid_json)
  end

  test "process treats non-numeric split values as missing after repair" do
    result = ArticleAnalyzer.process("analysis" => "{\"left\": [}")

    assert_equal [ 0, 100, 0 ], result.values_at(:bias_left_percent, :bias_center_percent, :bias_right_percent)
    assert_equal [ 100, 0 ], result.values_at(:factual_percent, :speculative_percent)
  end

  test "breadcrumbs are sent as Sentry::Breadcrumb objects, not extra: keywords" do
    recorded_breadcrumbs = []
    recording_add_breadcrumb = ->(breadcrumb, **options) do
      assert_empty options
      recorded_breadcrumbs << breadcrumb
    end

    Sentry.stub(:add_breadcrumb, recording_add_breadcrumb) do
      ArticleAnalyzer.process("analysis" => '{"left": 10, "center": 60, "right": 30, "factual": 40, "speculative": 60}')
    end

    assert_equal 3, recorded_breadcrumbs.size
    assert recorded_breadcrumbs.all? { |breadcrumb| breadcrumb.is_a?(Sentry::Breadcrumb) }
    assert_equal "ArticleAnalyzer.process", recorded_breadcrumbs.first.message
  end

  test "process raises on a response without JSON so the task fails" do
    assert_raises(ArgumentError) { ArticleAnalyzer.process("analysis" => "I cannot help with that.") }
  end

  test "unanalyzed_candidates skips analyzed and archived articles" do
    fresh    = create_article
    failed   = create_article(attrs: { analysis_status: "failed" })
    done     = create_article(attrs: { analysis_status: "completed" })
    archived = create_article(attrs: { archived: true })

    candidates = ArticleAnalyzer.unanalyzed_candidates
    assert_includes candidates, fresh
    assert_includes candidates, failed
    assert_not_includes candidates, done
    assert_not_includes candidates, archived
  end
end
