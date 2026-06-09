# BBC Farsi Rails App

A Rails 8 admin web app that fetches BBC Persian RSS feeds, rewrites articles using a local LLM (Ollama), translates them to Persian, and autoposts to Telegram channels.

LLM work is **not** done inside the web app. The app enqueues **tasks** in a
database-backed queue; a separate [worker client](worker/README.md) — which has
access to Ollama — claims tasks over a protected API, runs them, and posts the
results back. This decouples the web app from Ollama entirely (the worker can run
on a different, GPU-equipped machine).

## Tech Stack

- **Ruby** 3.3.8 / **Rails** 8
- **SQLite3** (development/test) / **PostgreSQL** (production, via `DATABASE_URL`) — database
- **DB-backed task queue** + standalone worker client — LLM work
- **Solid Cache** — `Rails.cache` store
- **Ollama** — local LLM inference, called by the worker (not the app)
- **feedjira + httparty** — RSS fetching
- **telegram-bot-ruby** — Telegram posting
- **Bootstrap 5** — admin UI
- **Kamal** — deployment

---

## Requirements

- Ruby 3.3.8 (see `.ruby-version`)
- Bundler
- SQLite3
- [Ollama](https://ollama.com) running locally

---

## Setup

### 1. Install dependencies

```bash
bundle install
```

### 2. Configure environment

Copy the example env file and fill in your values:

```bash
cp .env.example .env
```

| Variable | Description |
|---|---|
| `WORKER_API_TOKEN` | Shared bearer token for the worker API (`/api/tasks`). Must match the worker's env. |
| `TELEGRAM_BOT_TOKEN` | Your Telegram bot token |
| `TELEGRAM_CHANNEL` | Default Telegram channel (e.g. `@YourChannel`) |
| `ADMIN_USERNAME` | Admin login username for `/admin` |
| `ADMIN_PASSWORD` | Admin login password for `/admin` |
| `OLLAMA_URL` | Only used for the admin "debug curl" panels now — the app itself never calls Ollama (default `http://localhost:11434`) |

### 3. Set up the database

```bash
bin/rails db:prepare
```

### 4. Start the server

```bash
bin/dev
```

`bin/dev` just boots Puma (`bin/rails server` is equivalent). The web app only
enqueues tasks — to actually process them you also need to run the
[worker client](worker/README.md) somewhere with access to Ollama:

```bash
WORKER_API_TOKEN=your-shared-secret ruby worker/worker.rb
```

Visit `http://localhost:3000/admin` and log in with your `ADMIN_USERNAME` / `ADMIN_PASSWORD`.

---

## Ollama Setup

The app uses two models via Ollama:

| Purpose | Model |
|---|---|
| Article rewriting | `qwen3:14b` |
| Persian translation & refinement | `aya-expanse:32b` |

### Install Ollama

**macOS:**

```bash
brew install ollama
```

Or download the installer from [ollama.com/download](https://ollama.com/download).

**Linux:**

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

**Docker:**

```bash
docker run -d -p 11434:11434 --name ollama ollama/ollama
```

### Pull the required models

```bash
ollama pull qwen3:14b
ollama pull aya-expanse:32b
```

> `aya-expanse:32b` is a large model (~20 GB). Make sure you have sufficient disk space and RAM (or a GPU with enough VRAM).

### Start the Ollama server

```bash
ollama serve
```

By default Ollama listens on `http://localhost:11434`. Set `OLLAMA_URL` in your `.env` if you run it on a different host or port (e.g. a remote GPU server):

```
OLLAMA_URL=http://192.168.1.50:11434
```

### Verify Ollama is reachable

```bash
curl http://localhost:11434/api/tags
```

You should see a JSON list of your locally available models.

---

## Task Queue & Worker

The web app never calls Ollama. When you trigger a rewrite, translation, or
refine, it creates a **task** in the `tasks` table. A separate **worker client**
claims tasks over a protected API, runs them against Ollama, and posts the
results back.

```
 Rails app (task queue)  <──/api/tasks──>  worker  <──/api/chat──>  Ollama
```

Task API (all require `Authorization: Bearer $WORKER_API_TOKEN`):

| Endpoint | Purpose |
|---|---|
| `GET  /api/tasks/next` | Claim the next pending task (`204` when idle) |
| `POST /api/tasks/:id/complete` | Submit `{ "responses": { "<key>": "<text>" } }` |
| `POST /api/tasks/:id/fail` | Report failure `{ "error": "..." }` |

Run the worker wherever Ollama is reachable (it uses only the Ruby stdlib):

```bash
export WORKER_API_TOKEN=your-shared-secret   # must match the Rails app
export APP_URL=http://localhost:3000
export OLLAMA_URL=http://localhost:11434
ruby worker/worker.rb
```

See [worker/README.md](worker/README.md) for full configuration.

Browse the queue at **`/admin/tasks`** — filter by status/kind, inspect a task's
requests/responses, and retry failed tasks.

### Periodic work (RSS fetch + autopost)

These need no Ollama access, so they stay in the app. There is no built-in
scheduler anymore — drive them from the admin UI or an external cron:

| Command | Purpose |
|---|---|
| `bin/rails bbc:fetch` | Fetch enabled RSS feeds, create a rewrite task per new article |
| `bin/rails bbc:autopost` | Post active completed translations to autopost channels |

Example crontab:

```cron
*/30 * * * *  cd /path/to/app && bin/rails bbc:fetch    >> log/cron.log 2>&1
*/5  * * * *  cd /path/to/app && bin/rails bbc:autopost >> log/cron.log 2>&1
```

(The admin **Fetch now** button runs `bbc:fetch` synchronously; a completed
translation task also auto-posts inline.)

---

## Admin Interface

All admin routes are under `/admin` and protected by HTTP Basic Auth.

| Route | Description |
|---|---|
| `/admin` | Dashboard — counts and recent activity |
| `/admin/feeds` | Manage RSS feeds |
| `/admin/articles` | Browse articles, trigger rewrite |
| `/admin/rewrites` | View/edit rewrites, activate versions |
| `/admin/translations` | View/edit translations, post to Telegram |
| `/admin/telegram_channels` | Manage Telegram channels and autopost settings |
| `/admin/ollama_servers` | Manage Ollama servers and their model lists |
| `/admin/tasks` | Task queue — status/kind filters, request/response inspector, retry |

### Multi-server comparison

Each article's show page has two collapsible panels — **Run Rewrites on Targets** and **Run Translations on Targets** — that display every enabled server and its configured models as checkboxes. Selecting multiple server/model combos and clicking submit creates one task per selection. All results appear on the same page so you can compare outputs and activate the best version for posting.

---

## Docker / Kamal Deployment

Production runs on **PostgreSQL**. The connection comes entirely from the
`DATABASE_URL` environment variable (Solid Cache shares the same database — no
separate cache database). On boot the entrypoint runs `bin/rails db:prepare`,
which creates the schema (app tables + `solid_cache_entries`) on first deploy.

Build and run with Docker:

```bash
docker build -t bbcfarsi .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=$(cat config/master.key) \
  -e DATABASE_URL=postgres://user:password@db-host:5432/bbcfarsi_production \
  -e ADMIN_USERNAME=admin \
  -e ADMIN_PASSWORD=secret \
  -e WORKER_API_TOKEN=your-shared-secret \
  --name bbcfarsi bbcfarsi
```

> The web container does **not** need to reach Ollama. Run the
> [worker client](worker/README.md) separately (e.g. on the GPU host) with the
> same `WORKER_API_TOKEN` and `APP_URL` pointed at this app.

For Kamal deployments, see `.kamal/`. `WORKER_API_TOKEN` and `DATABASE_URL` are
wired in as secrets in `config/deploy.yml` / `.kamal/secrets` (set `DATABASE_URL`
in your shell/password manager before `kamal deploy`). A managed Postgres just
needs `DATABASE_URL`; to self-host Postgres on a server, see the commented
`accessories: db:` block in `config/deploy.yml`.

---

## Running Tests

```bash
bin/rails test
```
