# Worker Interface Design

This document is a prompt/specification for implementing the worker API interface in any Rails app so it can be served by the same `worker/worker.rb` pull-based LLM worker that the bbcfarsi app uses.

---

## Overview

The worker is a standalone Ruby script that lives wherever Ollama is reachable (potentially a different machine). It polls your Rails app for pending LLM tasks, runs them through Ollama, and posts results back. Your Rails app does **no LLM work** and never calls Ollama directly.

The contract is a small JSON/HTTP API over three endpoints, protected by a shared bearer token.

---

## What You Need to Build

### 1. Task model

Add a `tasks` table with these columns:

| Column | Type | Notes |
|---|---|---|
| `kind` | string | e.g. `"rewrite"`, `"translate"`, `"refine"` — whatever task types your app has |
| `status` | string | `pending` → `claimed` → `completed` / `failed` |
| `model` | string | Ollama model name, e.g. `"qwen3:14b"` |
| `ollama_url` | string | Optional per-task Ollama server URL; nil → worker uses its default |
| `requests` | jsonb/text (JSON) | Array of `{ key, messages }` objects — the chat turns to run |
| `responses` | jsonb/text (JSON) | Map of `{ key => content }` — filled by the worker on completion |
| `priority` | integer | Default 0; higher = claimed sooner |
| `claimed_at` | datetime | Set when the task is claimed |
| `completed_at` | datetime | Set when the task completes or fails |
| `error_message` | string | Filled on failure |
| `attempts` | integer | Default 0; incremented on each claim |
| `target_type` | string | Polymorphic parent (e.g. `"Rewrite"`, `"Translation"`) |
| `target_id` | integer | Polymorphic parent id |

The `requests` column is the key field. It is an array of objects, each with:

```json
[
  {
    "key": "content",
    "messages": [
      { "role": "system", "content": "You are ..." },
      { "role": "user",   "content": "Article text here" }
    ]
  }
]
```

Multiple entries in `requests` = multiple sequential Ollama chat calls per task. The worker runs them in order and collects `{ key => response_content }`.

### 2. Stale-task reclaim

Tasks that stay `claimed` for longer than 1 hour without a result are presumed dead. On every claim poll, return stale claimed tasks to `pending`. In your `Task` model:

```ruby
STALE_AFTER = 1.hour

scope :stale, -> { where(status: "claimed").where(claimed_at: ..STALE_AFTER.ago) }

def self.reclaim_stale!
  stale.each { |t| t.update!(status: "pending", claimed_at: nil) }
end
```

Call `reclaim_stale!` inside `claim_next!` so it's self-healing on every worker poll.

### 3. API controller

Mount the API at `/api/tasks`. Create `Api::BaseController < ActionController::API` that authenticates with a bearer token:

```ruby
class Api::BaseController < ActionController::API
  before_action :authenticate_worker!

  private

  def authenticate_worker!
    expected = ENV["WORKER_API_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s.sub(/\ABearer\s+/i, "")
    return if expected.present? &&
              ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
```

### 4. The three API endpoints

#### `GET /api/tasks/next`

Claims and returns the next pending task. The worker passes its available Ollama models as query params:

```
GET /api/tasks/next?models[]=qwen3:14b&models[]=llama3.2
```

When `models[]` is present, only tasks whose `model` is in that list should be returned. When absent, any pending task qualifies.

Steps:
1. Call `reclaim_stale!`
2. Query `pending` tasks ordered by `priority DESC, created_at ASC`
3. Filter by `model IN (models)` if models list is given
4. Lock and claim the first matching task: set `status: "claimed"`, `claimed_at: Time.current`, increment `attempts`
5. Return **200** with the task payload JSON, or **204** (no content) if the queue is empty or no compatible task exists.

**Response body (200):**

```json
{
  "id": 42,
  "kind": "rewrite",
  "model": "qwen3:14b",
  "ollama_url": "http://192.168.1.10:11434",
  "requests": [
    {
      "key": "content",
      "messages": [
        { "role": "system", "content": "You are a news editor..." },
        { "role": "user",   "content": "Title: …\n\nSummary text…" }
      ]
    }
  ]
}
```

`ollama_url` may be `null` — the worker falls back to its `OLLAMA_URL` env var.

#### `POST /api/tasks/:id/complete`

The worker posts back a map of response contents keyed by the request key:

```json
{
  "responses": {
    "content": "Rewritten article body...",
    "title": "Persian title...",
    "body": "Persian body..."
  }
}
```

Steps:
1. Find the task by id.
2. Store `responses` on the task record.
3. Run your post-processing logic (save to the target record, update statuses, chain next task if needed).
4. Set `status: "completed"`, `completed_at: Time.current`.
5. Return **200**:

```json
{ "id": 42, "status": "completed" }
```

#### `POST /api/tasks/:id/fail`

The worker posts this when Ollama returns an error:

```json
{ "error": "Ollama HTTP 500: ..." }
```

Steps:
1. Find the task by id.
2. Set `status: "failed"`, `error_message: params[:error]`.
3. Mark the target record as errored.
4. Return **200**:

```json
{ "id": 42, "status": "failed" }
```

### 5. Routes

```ruby
namespace :api do
  resources :tasks, only: [] do
    collection { get  :next,     action: :claim }
    member     { post :complete, :fail }
  end
end
```

Map `fail` to a `mark_failed` action to avoid overriding Ruby's `fail` keyword:

```ruby
member { post :complete; post :fail, action: :mark_failed }
```

### 6. Environment variable

Set `WORKER_API_TOKEN` in your app's `.env` / secrets. The worker's `.env` must have the same value.

---

## How the Worker Uses the Interface

```
loop:
  1. GET  <OLLAMA_URL>/api/tags          → discover available models
  2. GET  <APP_URL>/api/tasks/next?models[]=… → claim a task (or 204 → sleep)
  3. For each { key, messages } in task.requests:
       POST <task.ollama_url OR OLLAMA_URL>/api/chat
            { model, messages, stream: false }
       collect { key => response.message.content }
  4. POST <APP_URL>/api/tasks/<id>/complete  { responses: { key => content } }
     OR
     POST <APP_URL>/api/tasks/<id>/fail      { error: "..." }
  5. If 204 on step 2: sleep POLL_INTERVAL seconds, repeat
```

The worker sends `Authorization: Bearer <WORKER_API_TOKEN>` on every call to your app.

---

## Minimal Task Lifecycle

```
create task (status: pending)
  ↓
worker polls → claims task (status: claimed, claimed_at: now)
  ↓  (or times out → reclaim_stale! returns it to pending)
worker calls Ollama for each request
  ↓
POST /complete → status: completed   (save results, chain next task)
  OR
POST /fail    → status: failed       (save error)
```

---

## Chaining Tasks

After `complete!`, your app can automatically enqueue the next task. For example, a `rewrite` task completing can auto-create a `translate` task for the same article. This is entirely app-side logic — the worker just reports results and moves on.

---

## What the Worker Expects from Ollama

The worker calls `GET <ollama_url>/api/tags` to discover models:

```json
{
  "models": [
    { "name": "qwen3:14b", ... },
    { "name": "llama3.2", ... }
  ]
}
```

For each request, it calls `POST <ollama_url>/api/chat`:

```json
{ "model": "qwen3:14b", "messages": [...], "stream": false }
```

And reads `response.message.content`.

Your app does not interact with Ollama at all — it only stores the `requests` array and the `responses` map.

---

## Worker Configuration

The worker reads these env vars from its own `.env` (or real environment):

| Variable | Default | Purpose |
|---|---|---|
| `APP_URL` | `http://localhost:3000` | Base URL of your Rails app |
| `WORKER_API_TOKEN` | *(required)* | Shared secret — must match the app |
| `OLLAMA_URL` | `http://localhost:11434` | Fallback Ollama server |
| `POLL_INTERVAL` | `5` | Seconds to sleep when queue is empty |
| `OLLAMA_TIMEOUT` | `600` | HTTP read timeout for Ollama calls |
| `STATUS_PORT` | `4567` | Port for the worker status dashboard |
| `STATUS_BIND` | `0.0.0.0` | Bind address for the status server |

---

## Checklist for Your App

- [ ] `tasks` table with all columns above
- [ ] `Task` model with `pending`, `claimed`, `completed`, `failed` status lifecycle
- [ ] `Task.claim_next!(models:)` with `reclaim_stale!` folded in, using `SELECT FOR UPDATE` / `lock`
- [ ] `Api::BaseController` with bearer token auth from `WORKER_API_TOKEN`
- [ ] `GET /api/tasks/next` → 200 (task JSON) or 204
- [ ] `POST /api/tasks/:id/complete` → store responses, run post-processing
- [ ] `POST /api/tasks/:id/fail` → store error
- [ ] Routes mounted under `/api`
- [ ] `WORKER_API_TOKEN` set in environment
- [ ] Services that build `requests` arrays and process `responses` maps (app-specific)
