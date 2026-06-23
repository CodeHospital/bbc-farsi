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

# ── Status Server (stdlib HTTP, no framework) ─────────────────────────────

def humanize_duration(seconds)
  return "—" if seconds.nil?

  seconds = seconds.round
  return "#{seconds}s" if seconds < 60

  minutes, secs = seconds.divmod(60)
  return "#{minutes}m #{secs}s" if minutes < 60

  hours, mins = minutes.divmod(60)
  "#{hours}h #{mins}m"
end

def humanize_time(time)
  time ? time.strftime("%Y-%m-%d %H:%M:%S") : "—"
end

def h(value)
  CGI.escapeHTML(value.to_s)
end

def snapshot_as_json(snapshot)
  default_models_entry = snapshot[:models_cache][CONFIG.default_ollama_url]
  {
    phase:           snapshot[:phase],
    started_at:      snapshot[:started_at]&.iso8601,
    uptime_seconds:  (Time.now - snapshot[:started_at]).round,
    last_poll_at:    snapshot[:last_poll_at]&.iso8601,
    app_url:         CONFIG.app_url,
    ollama_url:      CONFIG.default_ollama_url,
    poll_interval:   CONFIG.poll_interval,
    concurrency:     CONFIG.concurrency,
    completed_count: snapshot[:completed_count],
    failed_count:    snapshot[:failed_count],
    ollama: {
      models:     default_models_entry&.dig(:models) || [],
      checked_at: default_models_entry&.dig(:checked_at)&.iso8601
    },
    active_tasks: snapshot[:active_tasks].map do |worker_id, task_info|
      {
        worker_id:       worker_id,
        id:              task_info[:id],
        kind:            task_info[:kind],
        model:           task_info[:model],
        ollama_url:      task_info[:ollama_url],
        request_key:     task_info[:request_key],
        request_index:   task_info[:request_index],
        request_count:   task_info[:request_count],
        started_at:      task_info[:started_at]&.iso8601,
        elapsed_seconds: task_info[:started_at] ? (Time.now - task_info[:started_at]).round : nil
      }
    end,
    history: snapshot[:history].map do |entry|
      {
        id:               entry[:id],
        worker_id:        entry[:worker_id],
        kind:             entry[:kind],
        model:            entry[:model],
        status:           entry[:status],
        error:            entry[:error],
        started_at:       entry[:started_at]&.iso8601,
        finished_at:      entry[:finished_at]&.iso8601,
        duration_seconds: entry[:duration]&.round
      }
    end
  }
end

def render_status_html(snapshot)
  uptime = humanize_duration(Time.now - snapshot[:started_at])
  phase  = snapshot[:phase]

  phase_color = { "processing" => "#0d6efd", "idle" => "#198754",
                  "starting" => "#6c757d", "error" => "#dc3545" }.fetch(phase, "#6c757d")

  default_models_entry = snapshot[:models_cache][CONFIG.default_ollama_url]
  models_list    = default_models_entry&.dig(:models) || []
  models_checked = default_models_entry&.dig(:checked_at)

  active_tasks_html =
    if snapshot[:active_tasks].any?
      snapshot[:active_tasks].map do |worker_id, task_info|
        elapsed = humanize_duration(Time.now - task_info[:started_at])
        step = if task_info[:request_count].to_i.positive?
          "request #{task_info[:request_index]}/#{task_info[:request_count]}" +
            (task_info[:request_key] ? " — #{h(task_info[:request_key])}" : "")
        else
          "—"
        end
        <<~HTML
          <tr>
            <td>#{h(worker_id)}</td>
            <td>##{h(task_info[:id])}&nbsp;<span class="tag">#{h(task_info[:kind])}</span></td>
            <td>#{h(task_info[:model])}</td>
            <td>#{step}</td>
            <td>#{h(elapsed)}</td>
          </tr>
        HTML
      end.join
    else
      %(<tr><td colspan="5" class="muted">No tasks in flight — workers waiting for work.</td></tr>)
    end

  models_html =
    if models_list.any?
      models_list.map { |m| %(<span class="pill">#{h(m)}</span>) }.join(" ")
    else
      %(<span class="muted">No models reported yet.</span>)
    end

  history_rows =
    if snapshot[:history].any?
      snapshot[:history].map do |entry|
        status_color = entry[:status] == "completed" ? "#198754" : "#dc3545"
        error_cell   = entry[:error] ? h(entry[:error]) : ""
        <<~ROW
          <tr>
            <td>##{h(entry[:id])}</td>
            <td>#{h(entry[:worker_id])}</td>
            <td><span class="tag">#{h(entry[:kind])}</span></td>
            <td>#{h(entry[:model])}</td>
            <td><span style="color:#{status_color};font-weight:600">#{h(entry[:status])}</span></td>
            <td>#{h(humanize_duration(entry[:duration]))}</td>
            <td>#{h(humanize_time(entry[:finished_at]))}</td>
            <td class="err">#{error_cell}</td>
          </tr>
        ROW
      end.join("\n")
    else
      %(<tr><td colspan="8" class="muted">No tasks processed yet.</td></tr>)
    end

  <<~HTML
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta http-equiv="refresh" content="3">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>BBC Farsi Worker — Status</title>
      <style>
        :root { color-scheme: light dark; }
        body { font-family: -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
               margin: 0; padding: 1.5rem; background: #f5f6f8; color: #1c1e21; }
        @media (prefers-color-scheme: dark) {
          body { background: #15171a; color: #e8eaed; }
          .card { background: #1f2226 !important; border-color: #2c3036 !important; }
          .kv th, table.hist th, table.active th { color: #9aa0a6 !important; }
          .pill, .tag { background: #2c3036 !important; }
        }
        h1 { font-size: 1.3rem; margin: 0 0 .25rem; }
        .sub { color: #6c757d; font-size: .85rem; margin-bottom: 1.25rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
                gap: 1rem; margin-bottom: 1rem; }
        .card { background: #fff; border: 1px solid #e3e6ea; border-radius: 10px;
                padding: 1rem 1.25rem; }
        .card h2 { font-size: .8rem; text-transform: uppercase; letter-spacing: .04em;
                   color: #6c757d; margin: 0 0 .75rem; }
        .badge { display: inline-block; padding: .15rem .6rem; border-radius: 999px;
                 color: #fff; font-size: .8rem; font-weight: 600; }
        .big { font-size: 1.6rem; font-weight: 700; }
        .muted { color: #8a9099; }
        table.kv { width: 100%; border-collapse: collapse; }
        table.kv th { text-align: left; color: #6c757d; font-weight: 500; width: 35%;
                      padding: .2rem .5rem .2rem 0; vertical-align: top; font-size: .9rem; }
        table.kv td { padding: .2rem 0; font-size: .9rem; word-break: break-word; }
        .pill, .tag { display: inline-block; background: #eef0f3; border-radius: 6px;
                      padding: .1rem .5rem; font-size: .82rem; margin: .1rem 0; }
        .tag { font-size: .72rem; text-transform: uppercase; letter-spacing: .03em; }
        table.hist, table.active { width: 100%; border-collapse: collapse; font-size: .85rem; }
        table.hist th, table.active th { text-align: left; color: #6c757d; font-weight: 500;
                        border-bottom: 1px solid #e3e6ea; padding: .4rem .5rem; }
        table.hist td, table.active td { padding: .4rem .5rem; border-bottom: 1px solid #eef0f3;
                        vertical-align: top; }
        td.err { color: #dc3545; max-width: 320px; word-break: break-word; }
        .counts { display: flex; gap: 1.5rem; }
        a { color: inherit; }
      </style>
    </head>
    <body>
      <h1>BBC Farsi Worker</h1>
      <div class="sub">
        app: <code>#{h(CONFIG.app_url)}</code> &nbsp;·&nbsp;
        ollama: <code>#{h(CONFIG.default_ollama_url)}</code> &nbsp;·&nbsp;
        concurrency: #{h(CONFIG.concurrency)} &nbsp;·&nbsp;
        poll: #{h(CONFIG.poll_interval)}s &nbsp;·&nbsp;
        uptime: #{h(uptime)} &nbsp;·&nbsp;
        <a href="/status.json">JSON</a>
      </div>

      <div class="grid">
        <div class="card">
          <h2>Status</h2>
          <p><span class="badge" style="background:#{phase_color}">#{h(phase)}</span></p>
          <p class="muted" style="font-size:.85rem;margin:.5rem 0 0">
            last poll: #{h(humanize_time(snapshot[:last_poll_at]))}
          </p>
        </div>

        <div class="card">
          <h2>Totals</h2>
          <div class="counts">
            <div><div class="big" style="color:#198754">#{h(snapshot[:completed_count])}</div>
                 <div class="muted">completed</div></div>
            <div><div class="big" style="color:#dc3545">#{h(snapshot[:failed_count])}</div>
                 <div class="muted">failed</div></div>
          </div>
        </div>

        <div class="card">
          <h2>Ollama models</h2>
          <p class="muted" style="font-size:.85rem;margin:0 0 .25rem">
            checked: #{h(humanize_time(models_checked))}
          </p>
          <div>#{models_html}</div>
        </div>
      </div>

      <div class="card" style="margin-bottom:1rem">
        <h2>Active workers (#{h(snapshot[:active_tasks].size)}/#{h(CONFIG.concurrency)})</h2>
        <table class="active">
          <thead>
            <tr><th>Worker</th><th>Task</th><th>Model</th><th>Step</th><th>Elapsed</th></tr>
          </thead>
          <tbody>
            #{active_tasks_html}
          </tbody>
        </table>
      </div>

      <div class="card">
        <h2>Recent history</h2>
        <table class="hist">
          <thead>
            <tr><th>Task</th><th>Worker</th><th>Kind</th><th>Model</th><th>Status</th>
                <th>Duration</th><th>Finished</th><th>Error</th></tr>
          </thead>
          <tbody>
            #{history_rows}
          </tbody>
        </table>
      </div>
    </body>
    </html>
  HTML
end

def write_http_response(client, code, content_type, body)
  reason = { 200 => "OK", 404 => "Not Found" }.fetch(code, "OK")
  client.write("HTTP/1.1 #{code} #{reason}\r\n")
  client.write("Content-Type: #{content_type}\r\n")
  client.write("Content-Length: #{body.bytesize}\r\n")
  client.write("Connection: close\r\n")
  client.write("\r\n")
  client.write(body)
end

def handle_status_request(client)
  request_line = client.gets
  return unless request_line

  method, path, = request_line.split(" ")
  while (line = client.gets) && line != "\r\n"; end

  if method != "GET"
    write_http_response(client, 404, "text/plain; charset=utf-8", "Not Found")
    return
  end

  case path.to_s.split("?").first
  when "/status.json"
    body = JSON.pretty_generate(snapshot_as_json(STATE.snapshot))
    write_http_response(client, 200, "application/json; charset=utf-8", body)
  when "/", "/index.html"
    write_http_response(client, 200, "text/html; charset=utf-8", render_status_html(STATE.snapshot))
  else
    write_http_response(client, 404, "text/plain; charset=utf-8", "Not Found")
  end
rescue StandardError => e
  error("Status server error: #{e.class}: #{e.message}")
ensure
  begin
    client&.close
  rescue StandardError
    nil
  end
end

def start_status_server
  server = TCPServer.new(CONFIG.status_bind, CONFIG.status_port)
  info("Status page at http://#{CONFIG.status_bind}:#{CONFIG.status_port}/")
  Thread.new do
    loop do
      begin
        handle_status_request(server.accept)
      rescue StandardError => e
        error("Status accept error: #{e.class}: #{e.message}")
      end
    end
  end
rescue StandardError => e
  warn("Could not start status server on #{CONFIG.status_bind}:#{CONFIG.status_port}: #{e.message}")
  nil
end

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

start_status_server

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
