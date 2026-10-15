require "test_helper"

class AppCredentialsTest < ActiveSupport::TestCase
  test "fetch treats blank strings as unset" do
    stub_credentials(llmarkt_api_key: "  ", app_base_url: "https://app.test")

    assert_nil AppCredentials.fetch(:llmarkt_api_key)
    assert_equal "https://app.test", AppCredentials.fetch(:app_base_url)
  end

  test "worker_api_token comes from credentials, never ENV" do
    ENV["WORKER_API_TOKEN"] = "env-token"
    stub_credentials(worker_api_token: nil)
    assert_nil AppCredentials.worker_api_token

    stub_credentials(worker_api_token: "cred-token")
    assert_equal "cred-token", AppCredentials.worker_api_token
  ensure
    ENV.delete("WORKER_API_TOKEN")
  end

  test "ollama_url falls back to the local default" do
    stub_credentials(ollama_url: nil)
    assert_equal "http://localhost:11434", AppCredentials.ollama_url

    stub_credentials(ollama_url: "http://gpu.local:11434")
    assert_equal "http://gpu.local:11434", AppCredentials.ollama_url
  end
end
