require "test_helper"

class OllamaServerTest < ActiveSupport::TestCase
  setup { OllamaServer.delete_all }

  test "pick_for_analysis prefers a configured analysis model" do
    OllamaServer.create!(name: "A rewrite box", url: "http://a:11434", rewrite_models: "qwen3:14b")
    analysis_server = OllamaServer.create!(name: "B analysis box", url: "http://b:11434", analyze_models: "gemma3:27b\nqwen3:32b")

    assert_equal [ analysis_server, "gemma3:27b" ], OllamaServer.pick_for_analysis
  end

  test "pick_for_analysis falls back to the rewrite model when no analysis model is set" do
    rewrite_server = OllamaServer.create!(name: "Local", url: "http://a:11434", rewrite_models: "qwen3:14b")
    assert_equal [ rewrite_server, "qwen3:14b" ], OllamaServer.pick_for_analysis
  end

  test "pick_for_analysis ignores disabled servers and returns nils when nothing is configured" do
    OllamaServer.create!(name: "Off", url: "http://a:11434", analyze_models: "gemma3:27b", enabled: false)
    assert_equal [ nil, nil ], OllamaServer.pick_for_analysis
  end

  test "analyze_model_list parses newlines and commas" do
    server = OllamaServer.new(analyze_models: "gemma3:27b, qwen3:14b\n\n llama3:8b ")
    assert_equal %w[gemma3:27b qwen3:14b llama3:8b], server.analyze_model_list
  end
end
