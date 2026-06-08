# BBC Farsi Task Worker

A standalone client that performs the LLM work for the BBC Farsi app. The Rails
app no longer talks to Ollama itself — it only enqueues **tasks**. This worker
(which has access to Ollama) claims tasks over a protected API, runs them
against Ollama, and posts the results back.

The worker uses **only the Ruby standard library** (`net/http`, `json`), so it
runs anywhere Ruby is installed — including the machine that hosts Ollama, which
may be different from the one running the Rails app.

## How it works

```
 ┌────────────┐   GET /api/tasks/next    ┌──────────┐   POST /api/chat   ┌────────┐
 │ Rails app  │ <──────────────────────  │  worker  │ ─────────────────> │ Ollama │
 │ (task queue)│  POST /api/tasks/:id/... │          │ <───────────────── │        │
 └────────────┘ ──────────────────────>  └──────────┘     completion     └────────┘
```

1. `GET  /api/tasks/next` — claim the next pending task (`204` when idle).
2. For each request in the task, `POST` to Ollama's `/api/chat`.
3. `POST /api/tasks/:id/complete` with `{ "responses": { "<key>": "<text>" } }`
   (or `POST /api/tasks/:id/fail` with `{ "error": "..." }` on failure).

Each task carries everything the worker needs: the `model`, an `ollama_url`
(the server the admin selected, or `null`), and a list of `requests`, each with
a `key` and a chat `messages` array. The worker is generic — all prompt logic
lives in the Rails app.

The queue claims **higher-priority tasks first** (priority is set by the admin).
There is also a **visibility timeout**: if a claimed task isn't reported back
within one hour, the app assumes the worker died and returns the task to
`pending` so it can be re-claimed. Normal runs finish well inside that window
(`OLLAMA_TIMEOUT` defaults to 600s), so this only triggers on a crashed or
hung worker.

## Configuration

| Env var            | Default                  | Description |
|--------------------|--------------------------|-------------|
| `WORKER_API_TOKEN` | — (required)             | Shared bearer token; must match the Rails app. |
| `APP_URL`          | `http://localhost:3000`  | Base URL of the Rails app. |
| `OLLAMA_URL`       | `http://localhost:11434` | Fallback Ollama URL when a task has no server URL. |
| `POLL_INTERVAL`    | `5`                      | Seconds to wait when the queue is empty. |
| `OLLAMA_TIMEOUT`   | `600`                    | HTTP read timeout (seconds) for Ollama calls. |

Configuration can also live in a `.env` file next to `worker.rb` (one
`KEY=value` per line; `#` comments and an optional `export` prefix are allowed).
The worker loads it on startup using only the standard library — no `dotenv`
gem. **Real environment variables take precedence over `.env` values**, so you
can still override any setting on the command line.

```ini
# worker/.env
WORKER_API_TOKEN=your-shared-secret
APP_URL=http://localhost:5000
OLLAMA_URL=http://localhost:11434
```

## Run

```bash
# Using worker/.env:
ruby worker/worker.rb

# Or with explicit environment variables (these override .env):
export WORKER_API_TOKEN=your-shared-secret
export APP_URL=https://app.example.com
export OLLAMA_URL=http://localhost:11434
ruby worker/worker.rb
```

The same `WORKER_API_TOKEN` must be set in the Rails app's environment so the
two sides agree on the bearer token.

## Security

- Every API request must send `Authorization: Bearer $WORKER_API_TOKEN`.
  Requests without a valid token get `401`.
- The token is compared with a constant-time check on the server.
- Keep the token secret; rotate it by updating both the worker and the app.
