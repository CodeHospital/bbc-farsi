# BBC Farsi Rails App

A Rails 8 admin web app that fetches BBC Persian RSS feeds, rewrites articles using a local LLM (Ollama), translates them to Persian, and autoposts to Telegram channels.

## Tech Stack

- **Ruby** 3.3.8 / **Rails** 8
- **SQLite3** — database
- **Solid Queue** — background jobs + recurring cron
- **Ollama** — local LLM inference (rewriting + translation)
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
| `OLLAMA_URL` | Ollama API base URL (default: `http://localhost:11434`) |
| `TELEGRAM_BOT_TOKEN` | Your Telegram bot token |
| `TELEGRAM_CHANNEL` | Default Telegram channel (e.g. `@YourChannel`) |
| `ADMIN_USERNAME` | HTTP Basic Auth username for `/admin` |
| `ADMIN_PASSWORD` | HTTP Basic Auth password for `/admin` |

### 3. Set up the database

```bash
bin/rails db:prepare
```

### 4. Start the server

```bash
bin/rails server
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

## Background Jobs

Jobs run via Solid Queue. Start the worker alongside the Rails server:

```bash
bin/jobs
```

Recurring tasks (configured in `config/recurring.yml`):

| Schedule | Job |
|---|---|
| Every 30 min | `FetchFeedsJob` — pulls all enabled RSS feeds |
| Every 5 min | `AutopostJob` — posts completed translations to autopost channels |

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

### Multi-server comparison

Each article's show page has two collapsible panels — **Run Rewrites on Targets** and **Run Translations on Targets** — that display every enabled server and its configured models as checkboxes. Selecting multiple server/model combos and clicking submit queues one job per selection. All results appear on the same page so you can compare outputs and activate the best version for posting.

---

## Docker / Kamal Deployment

Build and run with Docker:

```bash
docker build -t bbcfarsi .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=$(cat config/master.key) \
  -e ADMIN_USERNAME=admin \
  -e ADMIN_PASSWORD=secret \
  -e OLLAMA_URL=http://host.docker.internal:11434 \
  --name bbcfarsi bbcfarsi
```

> When running the app in Docker, set `OLLAMA_URL=http://host.docker.internal:11434` so the container can reach Ollama on the host machine.

For Kamal deployments, see `.kamal/`.

---

## Running Tests

```bash
bin/rails test
```
