#!/usr/bin/env ruby
# frozen_string_literal: true

# BBC Farsi task worker.
#
# A standalone client that runs wherever Ollama is reachable — which may be a
# different machine than the Rails app — and drives the LLM work:
#
#   1. GET  {APP_URL}/api/tasks/next         -> claim the next pending task
#   2. For each request in the task, POST to Ollama's /api/chat
#   3. POST {APP_URL}/api/tasks/:id/complete -> { responses: { key => content } }
#      (or /fail on an Ollama error)
#
# All API calls send `Authorization: Bearer <WORKER_API_TOKEN>`.
#
# It also serves a small status page (stdlib HTTP server, no framework) showing
# what the worker is doing right now, a history of recent tasks, and the Ollama
# models / reachability — browse to http://<host>:<STATUS_PORT>/.
#
# Configuration (environment variables, or worker/.env):
#   APP_URL           Base URL of the Rails app   (default http://localhost:3000)
#   WORKER_API_TOKEN  Shared bearer token         (required)
#   OLLAMA_URL        Fallback Ollama base URL    (default http://localhost:11434)
#                     Used only when a task has no server URL of its own.
#   POLL_INTERVAL     Seconds to wait when idle   (default 5)
#   OLLAMA_TIMEOUT    HTTP read timeout (seconds) (default 600)
#   STATUS_PORT       Status page port            (default 4567)
#   STATUS_BIND       Status page bind address    (default 0.0.0.0)
#
# Run:  bundle exec ruby worker.rb   (from the worker/ directory)
#    or WORKER_API_TOKEN=secret bundle exec ruby worker.rb

require "bundler/setup"
require "dotenv"
require "net/http"
require "json"
require "uri"
require "socket"
require "cgi"
require "time"

$stdout.sync = true

# Load worker/.env; real env vars take precedence.
Dotenv.load(File.join(__dir__, ".env"))

APP_URL          = ENV.fetch("APP_URL", "http://localhost:3000").chomp("/")
WORKER_API_TOKEN = ENV.fetch("WORKER_API_TOKEN") { abort "WORKER_API_TOKEN is required" }
DEFAULT_OLLAMA   = ENV.fetch("OLLAMA_URL", "http://localhost:11434").chomp("/")
POLL_INTERVAL    = Integer(ENV.fetch("POLL_INTERVAL", "5"))
OLLAMA_TIMEOUT   = Integer(ENV.fetch("OLLAMA_TIMEOUT", "600"))
STATUS_PORT      = Integer(ENV.fetch("STATUS_PORT", "4567"))
STATUS_BIND      = ENV.fetch("STATUS_BIND", "0.0.0.0")

MAX_HISTORY = 50

# ── Shared worker state (thread-safe) ─────────────────────────────────────────

# Holds everything the status page renders. The main loop mutates it; the HTTP
# server thread reads snapshots. All access is guarded by a single mutex.
class WorkerState
  def initialize
    @mutex            = Mutex.new
    @started_at       = Time.now
    @phase            = "starting" # starting | idle | processing | error
    @current          = nil        # hash describing the in-flight task
    @history          = []         # most-recent-first list of finished tasks
    @models           = []
    @ollama_reachable = false
    @ollama_checked_at = nil
    @last_poll_at     = nil
    @completed_count  = 0
    @failed_count     = 0
  end

  def set_phase(phase)
    @mutex.synchronize { @phase = phase }
  end

  def mark_poll
    @mutex.synchronize { @last_poll_at = Time.now }
  end

  def set_models(models:, reachable:)
    @mutex.synchronize do
      @models = models
      @ollama_reachable = reachable
      @ollama_checked_at = Time.now
    end
  end

  def begin_task(task)
    @mutex.synchronize do
      @phase = "processing"
      @current = {
        id:           task["id"],
        kind:         task["kind"],
        model:        task["model"],
        ollama_url:   task["ollama_url"],
        request_count: Array(task["requests"]).size,
        request_index: 0,
        request_key:  nil,
        started_at:   Time.now
      }
    end
  end

  def set_current_request(key, index, total)
    @mutex.synchronize do
      next unless @current

      @current[:request_key]   = key
      @current[:request_index] = index
      @current[:request_count] = total
    end
  end

  def finish_task(status:, error: nil)
    @mutex.synchronize do
      if @current
        finished_at = Time.now
        @history.unshift(
          id:          @current[:id],
          kind:        @current[:kind],
          model:       @current[:model],
          status:      status,
          error:       error,
          started_at:  @current[:started_at],
          finished_at: finished_at,
          duration:    finished_at - @current[:started_at]
        )
        @history = @history.first(MAX_HISTORY)
      end
      @completed_count += 1 if status == "completed"
      @failed_count    += 1 if status == "failed"
      @current = nil
      @phase   = "idle"
    end
  end

  # A deep-ish copy of the current state for read-only rendering.
  def snapshot
    @mutex.synchronize do
      {
        started_at:        @started_at,
        phase:             @phase,
        current:           @current && @current.dup,
        history:           @history.map(&:dup),
        models:            @models.dup,
        ollama_reachable:  @ollama_reachable,
        ollama_checked_at: @ollama_checked_at,
        last_poll_at:      @last_poll_at,
        completed_count:   @completed_count,
        failed_count:      @failed_count
      }
    end
  end
end

STATE = WorkerState.new

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

# ── Ollama model discovery ───────────────────────────────────────────────────

# Query the local Ollama instance for available models via GET /api/tags.
# Returns { reachable: Boolean, models: ["qwen3:14b", …] }.
def fetch_ollama_models(base_url)
  uri = URI("#{base_url}/api/tags")
  res = http_for(uri).request(Net::HTTP::Get.new(uri))
  return { reachable: false, models: [] } unless res.code.to_i == 200

  data = JSON.parse(res.body)
  models = Array(data["models"]).map { |m| m["name"].to_s.split(":").first }.reject(&:empty?)
  { reachable: true, models: models }
rescue StandardError => e
  log("Could not query Ollama models: #{e.message}")
  { reachable: false, models: [] }
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
  base_url  = (task["ollama_url"] || DEFAULT_OLLAMA).to_s.chomp("/")
  model     = task["model"]
  requests  = Array(task["requests"])
  responses = {}

  requests.each_with_index do |request, index|
    key = request["key"]
    STATE.set_current_request(key, index + 1, requests.size)
    log("  -> #{key} (#{model} @ #{base_url}) [#{index + 1}/#{requests.size}]")
    responses[key] = ollama_chat(base_url, model, request["messages"])
  end

  responses
end

def claim_and_run
  STATE.mark_poll
  discovery = fetch_ollama_models(DEFAULT_OLLAMA)
  STATE.set_models(models: discovery[:models], reachable: discovery[:reachable])
  available_models = discovery[:models]
  log("Available models: #{available_models.any? ? available_models.join(', ') : '(none found — accepting any task)'}") if available_models.any?

  path = "/api/tasks/next"
  if available_models.any?
    query = available_models.map { |m| "models[]=#{URI.encode_www_form_component(m)}" }.join("&")
    path  = "#{path}?#{query}"
  end

  res = api_get(path)

  case res.code.to_i
  when 204
    STATE.set_phase("idle")
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
  STATE.begin_task(task)

  begin
    responses = process(task)
    api_post("/api/tasks/#{task['id']}/complete", { responses: responses })
    log("Completed task ##{task['id']}")
    STATE.finish_task(status: "completed")
  rescue StandardError => e
    log("Task ##{task['id']} failed: #{e.message}")
    api_post("/api/tasks/#{task['id']}/fail", { error: e.message })
    STATE.finish_task(status: "failed", error: e.message)
  end

  true
end

# ── Status HTTP server (stdlib only) ──────────────────────────────────────────

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

# Build the JSON form of a snapshot (Time objects rendered as ISO-8601 strings).
def snapshot_as_json(snapshot)
  current = snapshot[:current]
  {
    phase:             snapshot[:phase],
    started_at:        snapshot[:started_at]&.iso8601,
    uptime_seconds:    (Time.now - snapshot[:started_at]).round,
    last_poll_at:      snapshot[:last_poll_at]&.iso8601,
    app_url:           APP_URL,
    ollama_url:        DEFAULT_OLLAMA,
    poll_interval:     POLL_INTERVAL,
    completed_count:   snapshot[:completed_count],
    failed_count:      snapshot[:failed_count],
    ollama: {
      reachable:  snapshot[:ollama_reachable],
      checked_at: snapshot[:ollama_checked_at]&.iso8601,
      models:     snapshot[:models]
    },
    current: current && {
      id:            current[:id],
      kind:          current[:kind],
      model:         current[:model],
      ollama_url:    current[:ollama_url],
      request_key:   current[:request_key],
      request_index: current[:request_index],
      request_count: current[:request_count],
      started_at:    current[:started_at]&.iso8601,
      elapsed_seconds: current[:started_at] ? (Time.now - current[:started_at]).round : nil
    },
    history: snapshot[:history].map do |entry|
      {
        id:          entry[:id],
        kind:        entry[:kind],
        model:       entry[:model],
        status:      entry[:status],
        error:       entry[:error],
        started_at:  entry[:started_at]&.iso8601,
        finished_at: entry[:finished_at]&.iso8601,
        duration_seconds: entry[:duration]&.round
      }
    end
  }
end

def h(value)
  CGI.escapeHTML(value.to_s)
end

def render_status_html(snapshot)
  uptime  = humanize_duration(Time.now - snapshot[:started_at])
  phase   = snapshot[:phase]
  current = snapshot[:current]

  phase_color = { "processing" => "#0d6efd", "idle" => "#198754",
                  "starting" => "#6c757d", "error" => "#dc3545" }.fetch(phase, "#6c757d")

  ollama_ok    = snapshot[:ollama_reachable]
  ollama_color = ollama_ok ? "#198754" : "#dc3545"
  ollama_label = ollama_ok ? "reachable" : "unreachable"

  current_html =
    if current
      elapsed = humanize_duration(Time.now - current[:started_at])
      step = if current[:request_count].to_i.positive?
               "request #{current[:request_index]}/#{current[:request_count]}" +
                 (current[:request_key] ? " — #{h(current[:request_key])}" : "")
      else
               "—"
      end
      <<~HTML
        <table class="kv">
          <tr><th>Task</th><td>##{h(current[:id])} <span class="tag">#{h(current[:kind])}</span></td></tr>
          <tr><th>Model</th><td>#{h(current[:model])}</td></tr>
          <tr><th>Ollama</th><td>#{h(current[:ollama_url] || DEFAULT_OLLAMA)}</td></tr>
          <tr><th>Step</th><td>#{step}</td></tr>
          <tr><th>Elapsed</th><td>#{h(elapsed)}</td></tr>
          <tr><th>Started</th><td>#{h(humanize_time(current[:started_at]))}</td></tr>
        </table>
      HTML
    else
      %(<p class="muted">No task in flight — waiting for work.</p>)
    end

  models_html =
    if snapshot[:models].any?
      snapshot[:models].map { |m| %(<span class="pill">#{h(m)}</span>) }.join(" ")
    else
      %(<span class="muted">No models reported.</span>)
    end

  history_rows =
    if snapshot[:history].any?
      snapshot[:history].map do |entry|
        status_color = entry[:status] == "completed" ? "#198754" : "#dc3545"
        error_cell   = entry[:error] ? h(entry[:error]) : ""
        <<~ROW
          <tr>
            <td>##{h(entry[:id])}</td>
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
      %(<tr><td colspan="7" class="muted">No tasks processed yet.</td></tr>)
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
          .kv th, table.hist th { color: #9aa0a6 !important; }
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
        table.hist { width: 100%; border-collapse: collapse; font-size: .85rem; }
        table.hist th { text-align: left; color: #6c757d; font-weight: 500;
                        border-bottom: 1px solid #e3e6ea; padding: .4rem .5rem; }
        table.hist td { padding: .4rem .5rem; border-bottom: 1px solid #eef0f3;
                        vertical-align: top; }
        td.err { color: #dc3545; max-width: 320px; word-break: break-word; }
        .counts { display: flex; gap: 1.5rem; }
        a { color: inherit; }
      </style>
    </head>
    <body>
      <h1>BBC Farsi Worker</h1>
      <div class="sub">
        app: <code>#{h(APP_URL)}</code> &nbsp;·&nbsp;
        ollama: <code>#{h(DEFAULT_OLLAMA)}</code> &nbsp;·&nbsp;
        poll: #{h(POLL_INTERVAL)}s &nbsp;·&nbsp;
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
          <h2>Ollama</h2>
          <p><span class="badge" style="background:#{ollama_color}">#{h(ollama_label)}</span></p>
          <p class="muted" style="font-size:.85rem;margin:.5rem 0 .25rem">
            checked: #{h(humanize_time(snapshot[:ollama_checked_at]))}
          </p>
          <div>#{models_html}</div>
        </div>
      </div>

      <div class="card" style="margin-bottom:1rem">
        <h2>Current activity</h2>
        #{current_html}
      </div>

      <div class="card">
        <h2>Recent history</h2>
        <table class="hist">
          <thead>
            <tr><th>Task</th><th>Kind</th><th>Model</th><th>Status</th>
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
  # Drain the rest of the request headers.
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
  log("Status server error: #{e.class}: #{e.message}")
ensure
  begin
    client&.close
  rescue StandardError
    nil
  end
end

def start_status_server
  server = TCPServer.new(STATUS_BIND, STATUS_PORT)
  log("Status page at http://#{STATUS_BIND}:#{STATUS_PORT}/")
  Thread.new do
    loop do
      begin
        handle_status_request(server.accept)
      rescue StandardError => e
        log("Status accept error: #{e.class}: #{e.message}")
      end
    end
  end
rescue StandardError => e
  log("Could not start status server on #{STATUS_BIND}:#{STATUS_PORT}: #{e.message}")
  nil
end

# ── Main loop ───────────────────────────────────────────────────────────────

log("Worker started — app=#{APP_URL} ollama=#{DEFAULT_OLLAMA} poll=#{POLL_INTERVAL}s")
start_status_server

loop do
  begin
    did_work = claim_and_run
    sleep(POLL_INTERVAL) unless did_work
  rescue Interrupt
    log("Shutting down.")
    break
  rescue StandardError => e
    STATE.set_phase("error")
    log("Loop error: #{e.class}: #{e.message}")
    sleep(POLL_INTERVAL)
  end
end
