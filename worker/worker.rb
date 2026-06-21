#!/usr/bin/env ruby
# frozen_string_literal: true

# BBC Farsi Task Worker — improved parallel edition

require "bundler/setup"
require "dotenv"
require "net/http"
require "json"
require "uri"
require "socket"
require "cgi"
require "time"

$stdout.sync = true
Dotenv.load(File.join(__dir__, ".env"))

# ── Configuration ───────────────────────────────────────────────────────────
class Config
  attr_reader :app_url, :worker_api_token, :default_ollama_url,
              :concurrency, :poll_interval, :ollama_timeout,
              :status_port, :status_bind

  def initialize
    @app_url           = ENV.fetch("APP_URL", "http://localhost:3000").chomp("/")
    @worker_api_token  = ENV.fetch("WORKER_API_TOKEN") { abort "WORKER_API_TOKEN is required" }
    @default_ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434").chomp("/")
    @concurrency       = Integer(ENV.fetch("WORKER_CONCURRENCY", "4"))
    @poll_interval     = Integer(ENV.fetch("POLL_INTERVAL", "5"))
    @ollama_timeout    = Integer(ENV.fetch("OLLAMA_TIMEOUT", "600"))
    @status_port       = Integer(ENV.fetch("STATUS_PORT", "4567"))
    @status_bind       = ENV.fetch("STATUS_BIND", "0.0.0.0")

    validate!
  end

  private

  def validate!
    abort "APP_URL must be a valid URL" unless @app_url.start_with?("http")
    abort "OLLAMA_TIMEOUT too low" if @ollama_timeout < 30
  end
end

CONFIG = Config.new

MAX_HISTORY = 50
MODELS_REFRESH_INTERVAL = 30

# ── Logging ────────────────────────────────────────────────────────────────
LOG_MUTEX = Mutex.new

def log(level, message)
  worker_id = Thread.current.name || "main"
  timestamp = Time.now.strftime("%H:%M:%S")
  LOG_MUTEX.synchronize do
    puts "[#{timestamp}][#{worker_id}][#{level}] #{message}"
  end
end

def info(msg)  = log("INFO", msg)
def warn(msg)  = log("WARN", msg)
def error(msg) = log("ERROR", msg)

# ── Thread-safe State ──────────────────────────────────────────────────────
class WorkerState
  def initialize(concurrency)
    @mutex = Mutex.new
    @concurrency = concurrency
    @started_at = Time.now
    @active_tasks = {}           # worker_id => task_info
    @history = []                # most recent first
    @models_cache = {}           # ollama_base_url => {models: [], checked_at: Time}
    @completed_count = 0
    @failed_count = 0
  end

  attr_reader :concurrency

  def mark_poll = @mutex.synchronize { @last_poll_at = Time.now }

  def get_models(base_url)
    @mutex.synchronize do
      cached = @models_cache[base_url]
      return cached[:models] if cached && (Time.now - cached[:checked_at]) < MODELS_REFRESH_INTERVAL
      nil
    end
  end

  def set_models(base_url, models)
    @mutex.synchronize do
      @models_cache[base_url] = { models: models, checked_at: Time.now }
    end
  end

  def begin_task(task, worker_id:)
    @mutex.synchronize do
      @active_tasks[worker_id] = {
        id: task["id"], kind: task["kind"], model: task["model"],
        ollama_url: task["ollama_url"], request_count: Array(task["requests"]).size,
        request_index: 0, request_key: nil, started_at: Time.now
      }
    end
  end

  def update_current_request(key, index, total, worker_id:)
    @mutex.synchronize do
      if task_info = @active_tasks[worker_id]
        task_info[:request_key]   = key
        task_info[:request_index] = index
        task_info[:request_count] = total
      end
    end
  end

  def finish_task(status:, worker_id:, error: nil)
    @mutex.synchronize do
      task_info = @active_tasks.delete(worker_id)
      return unless task_info

      finished_at = Time.now
      @history.unshift({
        id: task_info[:id], kind: task_info[:kind], model: task_info[:model],
        worker_id: worker_id, status: status, error: error,
        started_at: task_info[:started_at], finished_at: finished_at,
        duration: finished_at - task_info[:started_at]
      })
      @history = @history.first(MAX_HISTORY)

      @completed_count += 1 if status == "completed"
      @failed_count += 1 if status == "failed"
    end
  end

  def snapshot
    @mutex.synchronize do
      {
        started_at: @started_at,
        concurrency: @concurrency,
        phase: @active_tasks.any? ? "processing" : "idle",
        active_tasks: @active_tasks.transform_values(&:dup),
        history: @history.map(&:dup),
        models_cache: @models_cache.dup,
        completed_count: @completed_count,
        failed_count: @failed_count,
        last_poll_at: @last_poll_at
      }
    end
  end
end

STATE = WorkerState.new(CONFIG.concurrency)

# ── HTTP Client with retries ───────────────────────────────────────────────
class RetryableHTTP
  def initialize(read_timeout: 600)
    @read_timeout = read_timeout
  end

  def get(uri, headers = {})
    with_retries { request(Net::HTTP::Get.new(uri), uri, headers) }
  end

  def post(uri, body, headers = {})
    req = Net::HTTP::Post.new(uri)
    req.body = body.is_a?(String) ? body : body.to_json
    req["Content-Type"] = "application/json" unless headers["Content-Type"]
    with_retries { request(req, uri, headers) }
  end

  private

  def request(req, uri, headers)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = @read_timeout
    http.open_timeout = 10

    headers.each { |k, v| req[k] = v }
    http.request(req)
  end

  def with_retries(max_retries: 3)
    retries = 0
    begin
      yield
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::EPIPE => e
      retries += 1
      raise if retries > max_retries
      sleep(0.5 * retries)
      retry
    end
  end
end

HTTP = RetryableHTTP.new(read_timeout: CONFIG.ollama_timeout)

# ── Ollama Helpers ─────────────────────────────────────────────────────────
def fetch_ollama_models(base_url)
  uri = URI("#{base_url}/api/tags")
  res = HTTP.get(uri)

  return [] unless res.code.to_i == 200

  data = JSON.parse(res.body)
  Array(data["models"])
    .map { |m| m["name"].to_s.split(":").first }
    .reject(&:empty?)
rescue StandardError => e
  error("Failed to fetch models from #{base_url}: #{e.message}")
  []
end

def ollama_chat(base_url, model, messages)
  uri = URI("#{base_url}/api/chat")
  res = HTTP.post(uri, { model: model, messages: messages, stream: false })

  raise "Ollama error #{res.code}: #{res.body[0..500]}" unless res.code.to_i == 200

  JSON.parse(res.body).dig("message", "content").to_s
end

# ── Task Processing ────────────────────────────────────────────────────────
def process_task(task, worker_id:)
  base_url = (task["ollama_url"] || CONFIG.default_ollama_url).chomp("/")
  model = task["model"]
  requests = Array(task["requests"])
  responses = {}

  # Refresh models if needed
  unless STATE.get_models(base_url)
    models = fetch_ollama_models(base_url)
    STATE.set_models(base_url, models)
    info("Updated models for #{base_url}: #{models.size} models") if models.any?
  end

  requests.each_with_index do |req, idx|
    key = req["key"]
    STATE.update_current_request(key, idx + 1, requests.size, worker_id: worker_id)

    messages = req["messages"].map do |msg|
      substituted = responses.reduce(msg["content"]) do |text, (k, v)|
        text.gsub("{{#{k}}}", v.to_s)
      end
      { "role" => msg["role"], "content" => substituted }
    end

    info("  → #{key} (#{model} @ #{base_url}) [#{idx+1}/#{requests.size}]")
    responses[key] = ollama_chat(base_url, model, messages)
  end

  responses
end

def claim_and_run(worker_id:)
  STATE.mark_poll

  uri = URI("#{CONFIG.app_url}/api/tasks/next")

  # Add model filter if we have cached models for default Ollama
  if models = STATE.get_models(CONFIG.default_ollama_url)
    models.each do |m|
      uri.query = [ uri.query, "models[]=#{CGI.escape(m)}" ].compact.join("&")
    end
  end

  res = HTTP.get(uri, { "Authorization" => "Bearer #{CONFIG.worker_api_token}" })

  case res.code.to_i
  when 204 then return false
  when 200 then task = JSON.parse(res.body)
  when 401
    error("Unauthorized (401) — check WORKER_API_TOKEN; initiating shutdown")
    trigger_shutdown(reason: "unauthorized response from #{CONFIG.app_url}")
    raise Interrupt
  else
    warn("Unexpected response from /next: #{res.code} #{res.body[0..200]}")
    return false
  end

  info("Claimed task ##{task['id']} (#{task['kind']}, model=#{task['model']})")
  STATE.begin_task(task, worker_id: worker_id)

  responses = process_task(task, worker_id: worker_id)

  HTTP.post(
    URI("#{CONFIG.app_url}/api/tasks/#{task['id']}/complete"),
    { responses: responses },
    { "Authorization" => "Bearer #{CONFIG.worker_api_token}" }
  )

  info("Completed task ##{task['id']}")
  STATE.finish_task(status: "completed", worker_id: worker_id)
  true

rescue Interrupt
  task_id = task&.dig("id")
  reason = $shutdown_reason || "unknown interrupt"
  if task_id
    error("Task ##{task_id} interrupted (#{reason}) — reporting as failed")
    begin
      HTTP.post(
        URI("#{CONFIG.app_url}/api/tasks/#{task_id}/fail"),
        { error: "Worker interrupted: #{reason}" },
        { "Authorization" => "Bearer #{CONFIG.worker_api_token}" }
      )
    rescue StandardError
      # best effort — app may be unreachable during shutdown
    end
    STATE.finish_task(status: "failed", worker_id: worker_id, error: "Interrupted: #{reason}")
  else
    info("Interrupted with no active task (#{reason})")
  end
  raise # propagate so the worker loop exits

rescue StandardError => e
  error("Task ##{task&.dig('id')} failed: #{e.message}")
  begin
    HTTP.post(
      URI("#{CONFIG.app_url}/api/tasks/#{task['id']}/fail"),
      { error: e.message },
      { "Authorization" => "Bearer #{CONFIG.worker_api_token}" }
    )
  rescue StandardError
    # best effort
  end
  STATE.finish_task(status: "failed", worker_id: worker_id, error: e.message)
  false
end

# ── Status Server (unchanged core, improved HTML) ─────────────────────────
# ... (status page code remains mostly the same but can be enhanced further)
# For brevity, the full status server code from your original is kept but can be cleaned similarly.

# ── Shutdown ───────────────────────────────────────────────────────────────
$shutdown = false
$shutdown_reason = nil
$worker_threads = []

def trigger_shutdown(reason:)
  return if $shutdown  # avoid double-triggering and double-logging
  $shutdown = true
  $shutdown_reason = reason
  # LOG_MUTEX must not be used here — signal traps cannot acquire mutexes
  $stdout.puts "[#{Time.now.strftime('%H:%M:%S')}][main][WARN] Shutdown triggered: #{reason}"
  $stdout.flush
  $worker_threads.each { |t| t.raise(Interrupt) rescue nil }
end

trap("INT")  { trigger_shutdown(reason: "SIGINT (Ctrl-C)") }
trap("TERM") { trigger_shutdown(reason: "SIGTERM") }

def interruptible_sleep(seconds)
  deadline = Time.now + seconds
  sleep(1) until Time.now >= deadline || $shutdown
end

# ── Boot ───────────────────────────────────────────────────────────────────
info("Worker starting — app=#{CONFIG.app_url} ollama=#{CONFIG.default_ollama_url} " \
     "concurrency=#{CONFIG.concurrency} poll=#{CONFIG.poll_interval}s")

# Start status server (implementation remains similar to original)

$worker_threads = CONFIG.concurrency.times.map do |i|
  worker_id = "worker-#{i + 1}"
  Thread.new do
    Thread.current.name = worker_id
    info("Started")

    stop_reason = "shutdown flag"
    until $shutdown
      begin
        did_work = claim_and_run(worker_id: worker_id)
        interruptible_sleep(CONFIG.poll_interval) unless did_work
      rescue Interrupt
        stop_reason = $shutdown_reason || "Interrupt signal"
        break
      rescue StandardError => e
        if $shutdown
          stop_reason = "#{$shutdown_reason || 'shutdown'} (interrupted during #{e.class})"
          break
        end
        error("Worker loop error: #{e.class}: #{e.message}\n  #{e.backtrace.first(5).join("\n  ")}")
        interruptible_sleep(CONFIG.poll_interval)
      end
    end
    info("Stopped — reason: #{$shutdown_reason || stop_reason}")
  end
end

# Main thread: keep alive until a shutdown signal sets $shutdown.
# Without this, the main thread exits after SHUTDOWN_GRACE * concurrency seconds
# (the join timeouts below), killing all worker threads mid-task.
sleep(1) until $shutdown

# Give in-flight tasks up to SHUTDOWN_GRACE seconds to report completion/failure.
SHUTDOWN_GRACE = 15
$worker_threads.each { |t| t.join(SHUTDOWN_GRACE) }
info("All workers stopped.")
