#!/usr/bin/env ruby
# frozen_string_literal: true

# BBC Farsi task worker.
#
# A standalone, dependency-free client (Ruby stdlib only). It runs wherever
# Ollama is reachable — which may be a different machine than the Rails app —
# and drives the LLM work the web app used to do in-process:
#
#   1. GET  {APP_URL}/api/tasks/next         -> claim the next pending task
#   2. For each request in the task, POST to Ollama's /api/chat
#   3. POST {APP_URL}/api/tasks/:id/complete -> { responses: { key => content } }
#      (or /fail on an Ollama error)
#
# All API calls send `Authorization: Bearer <WORKER_API_TOKEN>`.
#
# Configuration (environment variables):
#   APP_URL           Base URL of the Rails app   (default http://localhost:3000)
#   WORKER_API_TOKEN  Shared bearer token         (required)
#   OLLAMA_URL        Fallback Ollama base URL    (default http://localhost:11434)
#                     Used only when a task has no server URL of its own.
#   POLL_INTERVAL     Seconds to wait when idle   (default 5)
#
# Run:  WORKER_API_TOKEN=secret ruby worker/worker.rb

require "net/http"
require "json"
require "uri"

# ── .env loading ────────────────────────────────────────────────────────────
#
# Stdlib-only dotenv: read a `.env` file sitting next to this script and copy
# any keys it defines into ENV. Real environment variables win over file values,
# so `WORKER_API_TOKEN=… ruby worker/worker.rb` still overrides the file.
def load_dotenv(path = File.join(__dir__, ".env"))
  return unless File.exist?(path)

  File.foreach(path) do |raw_line|
    line = raw_line.strip
    next if line.empty? || line.start_with?("#")

    line = line.sub(/\Aexport\s+/, "")
    key, _separator, value = line.partition("=")
    key = key.strip
    next if key.empty?

    value = value.strip
    # Strip matching surrounding quotes, if any.
    value = value[1..-2] if value.length >= 2 && (value.start_with?('"') && value.end_with?('"') ||
                                                  value.start_with?("'") && value.end_with?("'"))

    ENV[key] ||= value
  end
end

load_dotenv

APP_URL          = ENV.fetch("APP_URL", "http://localhost:3000").chomp("/")
WORKER_API_TOKEN = ENV.fetch("WORKER_API_TOKEN") { abort "WORKER_API_TOKEN is required" }
DEFAULT_OLLAMA   = ENV.fetch("OLLAMA_URL", "http://localhost:11434").chomp("/")
POLL_INTERVAL    = Integer(ENV.fetch("POLL_INTERVAL", "5"))
OLLAMA_TIMEOUT   = Integer(ENV.fetch("OLLAMA_TIMEOUT", "600"))

# ── Ollama model discovery ───────────────────────────────────────────────────

# Query the local Ollama instance for available model names via GET /api/tags.
# Returns an array like ["qwen3:14b", "aya-expanse:32b"], or [] on any error.
def ollama_models(base_url)
  uri = URI("#{base_url}/api/tags")
  req = Net::HTTP::Get.new(uri)
  res = http_for(uri).request(req)
  return [] unless res.code.to_i == 200

  data = JSON.parse(res.body)
  Array(data["models"]).map { |m| m["name"].to_s }.reject(&:empty?)
rescue StandardError => e
  log("Could not query Ollama models: #{e.message}")
  []
end

def log(message)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
end

# ── HTTP helpers ────────────────────────────────────────────────────────────

def http_for(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.read_timeout = OLLAMA_TIMEOUT
  http
end

def api_get(path)
  uri = URI("#{APP_URL}#{path}")
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{WORKER_API_TOKEN}"
  http_for(uri).request(req)
end

def api_post(path, body)
  uri = URI("#{APP_URL}#{path}")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Bearer #{WORKER_API_TOKEN}"
  req["Content-Type"]  = "application/json"
  req.body = body.to_json
  http_for(uri).request(req)
end

# Run one chat request against Ollama, returning the assistant message content.
def ollama_chat(base_url, model, messages)
  uri = URI("#{base_url}/api/chat")
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "application/json"
  req.body = { model: model, messages: messages, stream: false }.to_json

  res = http_for(uri).request(req)
  raise "Ollama HTTP #{res.code}: #{res.body}" unless res.code.to_i == 200

  JSON.parse(res.body).dig("message", "content").to_s
end

# ── Task processing ─────────────────────────────────────────────────────────

def process(task)
  base_url = (task["ollama_url"] || DEFAULT_OLLAMA).to_s.chomp("/")
  model    = task["model"]
  responses = {}

  Array(task["requests"]).each do |request|
    key = request["key"]
    log("  -> #{key} (#{model} @ #{base_url})")
    responses[key] = ollama_chat(base_url, model, request["messages"])
  end

  responses
end

def claim_and_run
  available_models = ollama_models(DEFAULT_OLLAMA)
  log("Available models: #{available_models.any? ? available_models.join(', ') : '(none found — accepting any task)'}") if available_models.any?

  path = "/api/tasks/next"
  if available_models.any?
    query = available_models.map { |m| "models[]=#{URI.encode_www_form_component(m)}" }.join("&")
    path  = "#{path}?#{query}"
  end

  res = api_get(path)

  case res.code.to_i
  when 204
    return false # queue empty (or no compatible tasks)
  when 200
    task = JSON.parse(res.body)
  when 401
    abort "Unauthorized — check WORKER_API_TOKEN matches the Rails app."
  else
    log("Unexpected /next response #{res.code}: #{res.body}")
    return false
  end

  log("Claimed task ##{task['id']} (#{task['kind']}, model=#{task['model']})")

  begin
    responses = process(task)
    api_post("/api/tasks/#{task['id']}/complete", { responses: responses })
    log("Completed task ##{task['id']}")
  rescue StandardError => e
    log("Task ##{task['id']} failed: #{e.message}")
    api_post("/api/tasks/#{task['id']}/fail", { error: e.message })
  end

  true
end

# ── Main loop ───────────────────────────────────────────────────────────────

log("Worker started — app=#{APP_URL} ollama=#{DEFAULT_OLLAMA} poll=#{POLL_INTERVAL}s")

loop do
  begin
    did_work = claim_and_run
    sleep(POLL_INTERVAL) unless did_work
  rescue Interrupt
    log("Shutting down.")
    break
  rescue StandardError => e
    log("Loop error: #{e.class}: #{e.message}")
    sleep(POLL_INTERVAL)
  end
end
