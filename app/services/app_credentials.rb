# Single place the app reads its configuration secrets from: Rails encrypted
# credentials (`bin/rails credentials:edit`). ENV is NOT consulted — every
# app-level setting lives in credentials (see config/credentials.example.yml
# for the full list of keys). Only runtime/boot knobs (RAILS_MASTER_KEY,
# RAILS_ENV, PORT, RAILS_MAX_THREADS, WEB_CONCURRENCY, RAILS_LOG_LEVEL, …)
# stay in the environment.
#
# Boot-time config (config/database.yml, config/environments/production.rb,
# config/initializers/*) runs before the autoloader and so reads
# Rails.application.credentials directly with the same keys.
module AppCredentials
  module_function

  DEFAULT_OLLAMA_URL = "http://localhost:11434".freeze

  # Blank values count as unset.
  def fetch(key)
    value = Rails.application.credentials.dig(key)
    value.is_a?(String) ? value.presence : value
  end

  # Shared bearer token the worker client sends to /api/tasks.
  def worker_api_token = fetch(:worker_api_token)

  # Only used for the admin "debug curl" panels — the app never calls Ollama.
  def ollama_url = fetch(:ollama_url) || DEFAULT_OLLAMA_URL
end
