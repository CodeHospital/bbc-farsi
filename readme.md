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
| `ADMIN_USERNAME` | Bootstrap admin username (or Rails credentials `admin_username`, preferred) — used once by `bin/rails db:seed` to create the first admin `User` row (if no users exist yet). After that, log in with users managed at `/admin/users`. |
| `ADMIN_PASSWORD` | Bootstrap admin password (or credentials `admin_password`, see above) |
| `ADMIN_EMAIL` | Bootstrap admin email (or credentials `admin_email`, see above) — also where their password-reset emails would go |
| `OLLAMA_URL` | Only used for the admin "debug curl" panels now — the app itself never calls Ollama (default `http://localhost:11434`) |
| `RESEND_API_KEY` | Optional — [Resend](https://resend.com) API key, used as the SMTP password for outgoing mail (password resets). Prefer Rails credentials (`resend_api_key`) instead. |
| `SENDER_EMAIL` | Optional — the `From:` address for outgoing mail, e.g. `BBC Farsi <noreply@yourdomain.com>`. Prefer Rails credentials (`sender_email`) instead. Without this + `RESEND_API_KEY`, mail sending is a no-op. |

### 3. Set up the database

```bash
bin/rails db:prepare
bin/rails db:seed
```

`db:seed` also creates the first admin account (username/password/email from
`ADMIN_USERNAME`/`ADMIN_PASSWORD`/`ADMIN_EMAIL`) — but only if the `users`
table is empty. Once at least one admin exists, manage everyone (including
yourself) from `/admin/users` instead; the env vars are no longer read at
login time.

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

Visit `http://localhost:3000/admin` and log in with the admin account seeded above.

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

## LLM backends: llmarkt (primary) + Ollama worker (fallback)

LLM work always starts as a **task** in the `tasks` table (rewrite, translate,
refine, feature, tag). There are two ways a task gets executed:

1. **llmarkt (vibeearning) grid — primary, webhook-based.** When llmarkt is
   configured, a task is submitted to the grid the moment it is enqueued, and
   the result is delivered back via a webhook. No worker process is needed.

   ```
    Rails app ──POST /v1/jobs──▶ llmarkt grid ──webhook──▶ POST /api/llm_callbacks ──▶ Rails app
   ```

   Configure it in **Rails credentials** (preferred) or env vars — credentials
   win when both are set:

   | Credential key | Env fallback | Purpose |
   |---|---|---|
   | `llmarkt_api_url` | `LLMARKT_API_URL` | API base incl. version, e.g. `https://llmarkt.codehospital.com/api/v1` |
   | `llmarkt_api_key` | `LLMARKT_API_KEY` | Bearer token |
   | `app_base_url` | `APP_BASE_URL` | Public URL of **this** app, so llmarkt's webhook can reach it |
   | `llmarkt_model_match` | `LLMARKT_MODEL_MATCH` | `family` (default) or `exact` |

   ```bash
   bin/rails credentials:edit
   # llmarkt_api_url: https://llmarkt.codehospital.com/api/v1
   # llmarkt_api_key: <token>
   # app_base_url: https://news.example.com
   ```

   Each submitted job's `webhook_url` carries a signed token encoding the task id
   and request key, so `POST /api/llm_callbacks` knows where to route the result
   (not the worker bearer) and needs no job-mapping table. The webhook is **also**
   verified against the grid's `X-Vibe-Signature` header (HMAC-SHA256 of the raw
   body keyed with the API key, constant-time comparison) before it's trusted —
   a missing or invalid signature is rejected with `401`. Multi-step tasks (e.g.
   rewrite body → title) are run one job at a time, advancing on each callback.

   When the three required values are absent, llmarkt is **disabled** and tasks
   stay `pending` for the worker below — the app behaves exactly as before.

2. **Ollama worker — fallback / self-hosted.** A separate **worker client**
   claims `pending` tasks over a protected API, runs them against Ollama, and
   posts the results back. Used automatically for any task llmarkt didn't take
   (e.g. llmarkt disabled or a submission error).

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

All admin routes are under `/admin`, behind a session-based login backed by
the `User` model (`/admin/login`).

### Roles

| Role | Can access |
|---|---|
| `admin` | Everything, including infrastructure/config pages and `/admin/users` |
| `editor` | The editorial workflow: Dashboard, Articles, Rewrites, Translations, Task queue, Analytics, Telegram Posts (read-only log) |

Editors are redirected away from infrastructure/config pages (Feeds, Telegram
Channels, Ollama Servers, House Keeping, IP Geolocations, Users, Activity
Log) — those stay admin-only. Manage accounts at `/admin/users` (admin-only):
create an editor, change roles, reset passwords, or disable an account. A
built-in safeguard blocks removing/demoting the last active admin so nobody
can lock everyone out.

### Forgot password?

Every user has an email (used only for this). "Forgot password?" on the
login page (`/admin/password_resets/new`) emails a time-limited reset link
(20 minutes, via Rails' built-in `generates_token_for` — no separate tokens
table) using [`UserMailer`](app/mailers/user_mailer.rb). The response is
identical whether or not the email matches an account, so the flow can't be
used to enumerate registered users. See **Outgoing mail** below to configure
where those emails actually get sent.

### Who changed what

Every edit to a Rewrite's or Translation's text (and to Articles, Feeds,
Telegram Channels, Ollama Servers, and Users) is tracked via
[PaperTrail](https://github.com/paper-trail-gem/paper_trail): each Rewrite/
Translation show page has an **Edit history** panel listing every past
version with who made the change and the prior text; `/admin/activity_logs`
(admin-only) is a system-wide "who did what" log across all tracked models,
filterable by model type or user.

| Route | Description |
|---|---|
| `/admin` | Dashboard — counts and recent activity |
| `/admin/feeds` | Manage RSS feeds *(admin-only)* |
| `/admin/articles` | Browse articles, trigger rewrite |
| `/admin/rewrites` | View/edit rewrites, activate versions, edit history |
| `/admin/translations` | View/edit translations, post to Telegram, edit history |
| `/admin/telegram_channels` | Manage Telegram channels and autopost settings *(admin-only)* |
| `/admin/ollama_servers` | Manage Ollama servers and their model lists *(admin-only)* |
| `/admin/tasks` | Task queue — status/kind filters, request/response inspector, retry |
| `/admin/users` | Manage admin/editor accounts *(admin-only)* |
| `/admin/activity_logs` | System-wide audit log of who changed what *(admin-only)* |

### Multi-server comparison

Each article's show page has two collapsible panels — **Run Rewrites on Targets** and **Run Translations on Targets** — that display every enabled server and its configured models as checkboxes. Selecting multiple server/model combos and clicking submit creates one task per selection. All results appear on the same page so you can compare outputs and activate the best version for posting.

---

## Outgoing Mail (Resend)

Password reset emails are the only mail this app sends, delivered through
[Resend](https://resend.com)'s SMTP relay (`smtp.resend.com`) via
`ActionMailer`'s built-in `:smtp` delivery method — no extra gem required.

1. Create a Resend account, verify a sending domain, and grab an API key.
2. Set `RESEND_API_KEY` and `SENDER_EMAIL` (env or, preferred, Rails
   credentials as `resend_api_key` / `sender_email`) — see
   `app/services/mailer_config.rb`.
3. Set `APP_BASE_URL` (env or credentials — the same value used for llmarkt
   webhooks) so reset links point at the right host.

Without `RESEND_API_KEY`/`SENDER_EMAIL` configured, `perform_deliveries`
is off (see `config/initializers/action_mailer.rb`) — the forgot-password flow
still runs end to end, it just doesn't actually send anything. In tests,
`config/environments/test.rb` sets the `:test` delivery method, so specs
assert against `ActionMailer::Base.deliveries` instead of hitting the network.

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
  -e ADMIN_EMAIL=admin@yourdomain.com \
  -e WORKER_API_TOKEN=your-shared-secret \
  --name bbcfarsi bbcfarsi
```

`ADMIN_USERNAME`/`ADMIN_PASSWORD`/`ADMIN_EMAIL` only matter on the very first
boot — the entrypoint runs `db:seed`, which creates that one admin account if
the `users` table is empty. After that, manage accounts at `/admin/users`.

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
