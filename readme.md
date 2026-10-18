# Khabarestan Rails App

A Rails 8 admin web app that fetches international news RSS feeds (BBC, NYT and others), rewrites articles using a local LLM (Ollama), translates them to Persian, and autoposts to Telegram, Bale (bale.ai) and other Telegram-compatible channels.

LLM work is **not** done inside the web app. The app enqueues **tasks** in a
database-backed queue; a separate [worker client](worker/README.md) — which has
access to Ollama — claims tasks over a protected API, runs them, and posts the
results back. This decouples the web app from Ollama entirely (the worker can run
on a different, GPU-equipped machine).

## Tech Stack

- **Ruby** 3.3.8 / **Rails** 8
- **SQLite3** (development/test) / **PostgreSQL** (production, via the `database_url` credential) — database
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

### 2. Configure credentials

All app configuration lives in **Rails encrypted credentials**
(`config/credentials.yml.enc`). It's decrypted with `config/master.key`
locally, or with the `RAILS_MASTER_KEY` env var in production. The app does
**not** read ENV for any of these settings.

```bash
bin/rails credentials:edit     # opens the decrypted YAML in $EDITOR
bin/rails bbc:credentials      # lists which keys are set / MISSING (never prints values)
```

[`config/credentials.example.yml`](config/credentials.example.yml) is a
template with every key. Copy the ones you need into `credentials:edit`.

| Credential key | Required? | Purpose |
|---|---|---|
| `admin_username` / `admin_password` / `admin_email` | **yes** (app won't boot without them, except in test) | Bootstrap admin, used once by `bin/rails db:seed` to create the first admin `User` row if no users exist yet. After that, manage users at `/admin/users`. |
| `worker_api_token` | **yes** (worker API rejects every call without it) | Shared bearer token for the worker API (`/api/tasks`). Must match the worker's own `WORKER_API_TOKEN` env. |
| `database_url` | production only | PostgreSQL connection string, e.g. `postgres://user:password@host:5432/khabarestan_production`. Development/test use SQLite. |
| `app_base_url` | for llmarkt / Telegram admin bot / mail links | Public URL of this app. Also added to production's allowed hosts. |
| `llmarkt_api_url` / `llmarkt_api_key` / `llmarkt_model_match` | optional | llmarkt LLM grid (see below) |
| `resend_api_key` / `sender_email` | optional | Outgoing mail via Resend (see below) |
| `sentry_dsn` | optional | Error tracking (see below) |
| `telegram_admin_bot_token` / `telegram_admin_chat_id` / `telegram_admin_webhook_secret` | optional | Telegram admin notification bot (see below) |
| `ollama_url` | optional | Only used for the admin "debug curl" panels (default `http://localhost:11434`). The app itself never calls Ollama. |

Only runtime/boot knobs are still read from the environment: `RAILS_MASTER_KEY`,
`RAILS_ENV`, `PORT`, `RAILS_MAX_THREADS`, `WEB_CONCURRENCY`, `PIDFILE`,
`RAILS_LOG_LEVEL`, and `CI` (tests). The standalone worker (`worker/`) is a
separate program and keeps its own env config (see
[worker/README.md](worker/README.md)).

> **Migrating from `.env`:** each old env var maps to the lower-case credential
> of the same name (`WORKER_API_TOKEN` → `worker_api_token`, `DATABASE_URL` →
> `database_url`, `APP_BASE_URL` → `app_base_url`, …). Copy every value into
> `bin/rails credentials:edit`, then run `bin/rails bbc:credentials` to confirm.
> The old `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHANNEL` vars were only used by the
> legacy `update.rb` script. Channel tokens live on `/admin/telegram_channels`
> rows.

### 3. Set up the database

```bash
bin/rails db:prepare
bin/rails db:seed
```

`db:seed` also creates the first admin account (from the `admin_username` /
`admin_password` / `admin_email` credentials), but only if the `users`
table is empty. Once at least one admin exists, manage everyone (including
yourself) from `/admin/users`. The credentials are not read at login time.

### 4. Start the server

```bash
bin/dev
```

`bin/dev` just boots Puma (`bin/rails server` is equivalent). The web app only
enqueues tasks — to actually process them you also need to run the
[worker client](worker/README.md) somewhere with access to Ollama:

```bash
WORKER_API_TOKEN=<same value as the worker_api_token credential> ruby worker/worker.rb
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

By default Ollama listens on `http://localhost:11434`. If you run it on a different host or port (e.g. a remote GPU server), set `OLLAMA_URL` in the **worker's** environment. For the admin "debug curl" panels, also set the `ollama_url` credential:

```
OLLAMA_URL=http://192.168.1.50:11434          # worker env
ollama_url: http://192.168.1.50:11434         # bin/rails credentials:edit
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

   Configure it in **Rails credentials**:

   | Credential key | Purpose |
   |---|---|
   | `llmarkt_api_url` | API base incl. version, e.g. `https://llmarkt.codehospital.com/api/v1` |
   | `llmarkt_api_key` | Bearer token |
   | `app_base_url` | Public URL of **this** app, so llmarkt's webhook can reach it |
   | `llmarkt_model_match` | `family` (default) or `exact` |

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

Task API (all require `Authorization: Bearer <worker_api_token>`):

| Endpoint | Purpose |
|---|---|
| `GET  /api/tasks/next` | Claim the next pending task (`204` when idle) |
| `POST /api/tasks/:id/complete` | Submit `{ "responses": { "<key>": "<text>" } }` |
| `POST /api/tasks/:id/fail` | Report failure `{ "error": "..." }` |

Run the worker wherever Ollama is reachable (it uses only the Ruby stdlib):

```bash
export WORKER_API_TOKEN=your-shared-secret   # must match the app's worker_api_token credential
export APP_URL=http://localhost:3000
export OLLAMA_URL=http://localhost:11434
ruby worker/worker.rb
```

See [worker/README.md](worker/README.md) for full configuration.

Browse the queue at **`/admin/tasks`** — filter by status/kind, inspect a task's
requests/responses, and retry failed tasks.

### Feed sources

Every feed has a `source`, which decides two things: the fetcher used to pull it
(`FeedIngestor::FETCHER_CLASSES`) and the SSRF host allowlist that fetcher
enforces. `/admin/feeds` has a **Seed … Feeds** button per source that upserts
that source's whole catalog (idempotent — it matches on URL, so re-seeding never
duplicates or overwrites an edited feed).

| Source | Catalog | Feeds | Allowed hosts |
|---|---|---|---|
| `bbc` | `Feed::BBC_FEEDS` | 7 | `feeds.bbci.co.uk`, `www.bbc.co.uk`, `www.bbc.com` |
| `nyt` | `Feed::NYT_FEEDS` | 74 | `rss.nytimes.com`, `www.nytimes.com` |
| `adhocnews` | `Feed::ADHOCNEWS_FEEDS` | 12 | `www.ad-hoc-news.de` |
| `heise` | `Feed::HEISE_FEEDS` | 22 | `www.heise.de`, `www.telepolis.de` |
| `germannews` | `Feed::GERMANNEWS_FEEDS` | 50 | derived from the catalog (one host per publisher) |
| `australianews` | `Feed::AUSTRALIANEWS_FEEDS` | 15 | derived from the catalog |
| `israelnews` | `Feed::ISRAELNEWS_FEEDS` | 4 | derived from the catalog |

`germannews`, `australianews`, and `israelnews` are the odd ones: each is
**many publishers under one source** (germannews alone spans tagesschau, ZEIT,
SPIEGEL, FAZ, SZ, taz, 14 regional papers, and the ARD/ZDF-family public
broadcasters SWR/BR/WDR/NDR), so their allowlists are computed from the
catalog itself rather than hardcoded — a host is reachable only because a
shipped feed lives there. For the same reason those feeds carry a `site:` key
(the host their *articles* live on, which the fetcher's own host often isn't —
a broadcaster's several sections all resolve to one `publisher:`, e.g. every
NDR/WDR/tagesschau section attributes back to "NDR"/"WDR"/"tagesschau"), and
the public portal attributes each story to its real publisher via
`Feed#publisher_info` (`Feed.build_publisher_index`) instead of
`NewsHelper::SOURCE_INFO`. `israelnews` is deliberately small: it's limited to
English-language outlets, since `Prompt`'s "translate" prompt is written and
tuned specifically for English-to-Farsi (see the catalog's own comment in
`app/models/feed.rb` for what was tried and excluded, and why).

`FeedFetcher` never follows redirects, so a catalog entry must be the
**canonical** feed URL — a publisher that 301s its old feed path will otherwise
come back empty rather than erroring.

### Periodic work (RSS fetch + autopost)

These need no Ollama access, so they stay in the app.

**RSS fetch** can run on a per-feed hourly schedule, on demand, or both.

Each feed has a **Scheduled fetch** setting (`/admin/feeds` → Edit): either
*Disabled* (the default — the feed is never auto-fetched) or an hour of the
day, `00:00`–`23:00`. Hours are **server-local** (the sweep compares against
`Time.now.hour` on the machine running the app), so spreading feeds across the
24 slots staggers the load round the clock instead of hammering every source at
once. The Feeds index shows each feed's slot and when it was last auto-fetched.

What actually runs the hourly sweep (`FeedIngestor.run_scheduled`):

- **Built in, no setup needed**: `config/initializers/feed_fetch_scheduler.rb`
  runs a background thread inside the app server (`bin/rails server`) that
  polls every 5 minutes and fetches whatever is due.
- **Optional external cron**, if you'd rather not rely on the in-process
  thread. Safe to run alongside it — each feed is claimed with a conditional
  `UPDATE` (`feeds.last_scheduled_fetch_at`), so a feed is fetched at most once
  per hour slot no matter how many sweeps race:

```cron
0 * * * *  cd /path/to/app && bin/rails bbc:fetch_scheduled >> log/cron.log 2>&1
```

To fetch *everything* regardless of schedule, use the admin **Fetch now**
button, the per-feed **Fetch** button, or `bin/rails bbc:fetch` (which ignores
`fetch_hour` and pulls every enabled feed):

```cron
*/30 * * * *  cd /path/to/app && bin/rails bbc:fetch >> log/cron.log 2>&1
```

**Channels can be on any Telegram-compatible provider** — any messenger
whose bot API answers `<API base URL>/bot<token>/sendMessage` with
`chat_id` + `text`. At `/admin/telegram_channels` → New Channel, pick a
**Provider**:

| Provider | Endpoint | Message format |
|---|---|---|
| Telegram | `https://api.telegram.org` (or your own, e.g. a self-hosted Telegram Bot API server) | HTML (bold title) |
| Bale (bale.ai) | `https://tapi.bale.ai` | Plain text — Bale has no `parse_mode` |
| Other Telegram-compatible API | **required**: its API base URL (without `/bot<token>`) | You choose: plain, or HTML if it supports `parse_mode: "HTML"` |

"Other" also needs a **Provider name**, which is how its channels are labelled
in the admin and the Telegram admin bot. Create the bot on that messenger and
add it as an admin of the channel. Every provider shares the same queue,
pacing, posts log and enable/autopost toggles (all are `TelegramChannel` rows
with a `provider`). Telegram is sent through telegram-bot-ruby
(`TelegramPoster`); every other provider through plain HTTP (`BotApiPoster`),
whose posts end with "follow @<that channel> for more" when the channel id is
an `@username`. No env vars are needed: tokens live on the channel row.

**Autoposting is per-feed**: each feed has an **Autopost to** set of channels
(`/admin/feeds` → Edit, or the inline checkboxes on the index row), from any
provider — none by default. Once a translation for that feed completes,
`Autoposter.post_translation` queues it for exactly those channels (no fan-out
to every autopost-enabled channel). Delivery still requires each channel to be
both `enabled` **and** have its own Autopost toggle on
(`/admin/telegram_channels`) — a deliberate second gate, so a channel's
autoposting can be paused without editing every feed pointed at it
(`Feed#autopost_channels`). The Feeds index flags a checked channel in red
when it isn't currently enabled/autoposting, so a misconfiguration doesn't
fail silently.

**Channel posting** is queue-then-deliver, not instant, on every path —
autopost, a completed translation task, the web admin's "📤 Post" button, and
the Telegram admin bot's one-tap publish button all just *queue* a post
(`Publisher.post_to_channel`); actual delivery to Telegram is paced to
roughly 25-40 minutes apart per channel (`Autoposter::MIN_INTERVAL`/`JITTER`)
so a channel doesn't get a burst of messages at once. What actually calls
`Autoposter.run_all` to deliver due posts:

- **Built in, no setup needed**: `config/initializers/telegram_autopost_scheduler.rb`
  runs a background thread inside the app server (`bin/rails server`) that
  polls every minute. This is the primary delivery mechanism — nothing else
  to configure.
- **Optional external cron**, if you'd rather not rely on the in-process
  thread (e.g. it also drives the `unposted_for` sweep that queues new
  autopost-eligible translations, independent of the task-chain autopost):
  `bin/rails bbc:autopost`. Safe to run alongside the in-process poller —
  delivery is claim-then-atomic-update safe against double-sending.

```cron
*/5  * * * *  cd /path/to/app && bin/rails bbc:autopost >> log/cron.log 2>&1
```

---

## Telegram Admin Notification Bot

A separate Telegram bot (distinct from the per-channel publishing bots managed
at `/admin/telegram_channels`) DMs an admin/editor chat whenever a translation
finishes processing and becomes the active version — i.e. news that's ready
for a human decision. The message carries inline buttons so the admin can act
without opening the web admin at all:

1. 🔁 Request rewrite
2. 🌐 Request retranslation
3. ✨ Request refine
4. 📤 Publish to a channel on any provider (opens a channel-picker submenu;
   non-Telegram channels are suffixed with their provider, e.g. "(بله)"; with
   exactly one enabled channel it's a one-tap button instead)
5. 🌍 Publish / unpublish on the news portal
6. ✋ Mark for manual edit by editors

```
 Task#complete! ──sendMessage──▶ Telegram ──tap──▶ callback_query
                                     │                    │
                                     ▼                    ▼
                          admin's Telegram app   POST /api/telegram_admin/webhook
                                                          │
                                                          ▼
                                              TelegramAdminNotifier (edits the
                                              message in place + performs the
                                              action — same code paths as the
                                              equivalent admin-UI buttons)
```

Configure it in **Rails credentials**:

| Credential key | Purpose |
|---|---|
| `telegram_admin_bot_token` | The admin bot's token (from [@BotFather](https://t.me/BotFather)) |
| `telegram_admin_chat_id` | The user/group chat id to notify |
| `telegram_admin_webhook_secret` | Random secret Telegram echoes back on every webhook call, verified before trusting it |

```bash
bin/rails credentials:edit
# telegram_admin_bot_token: <token>
# telegram_admin_chat_id: <chat id>
# telegram_admin_webhook_secret: <long random string>
```

Then register the webhook once (needs the `app_base_url` credential set — the
same value used by llmarkt — so Telegram can reach this app):

```bash
bin/rails telegram_admin:set_webhook   # POST setWebhook, secret_token included
bin/rails telegram_admin:delete_webhook # to unregister
```

When `telegram_admin_bot_token`/`telegram_admin_chat_id` are absent, the
notifier is a no-op — no message is sent and nothing else changes. A flagged
"needs manual edit" translation shows a badge on `/admin/translations` and a
banner on its show page (filterable via the "Needs edit" toggle), whether it
was set from Telegram or from the web admin.

---

## Public Site: SEO, Social & LLM Discovery

- **SEO**: canonical + hreflang (fa/en) on every page, NewsArticle / BreadcrumbList / WebSite JSON-LD, `/sitemap.xml` (home, categories, stories, Google News tags for the last 2 days), dynamic `/robots.txt`. Search result pages are `noindex`.
- **Social**: Open Graph + Twitter Card tags (site-icon fallback when a story has no lead image) and share buttons on article pages.
- **LLMs / readers**: `/llms.txt` (site summary + latest articles), a Markdown twin of every story (`/news/<slug>.md`, `/en/news/<slug>.md`), and RSS feeds at `/feed.xml` and `/en/feed.xml`.

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

### Edit approval (restricted editors)

Tick **Edits need approval** on an editor's account (`/admin/users` → Edit) to
put their manual edits through review. When a restricted editor saves a
Translation (title/body) or Rewrite (content), nothing changes on the live
record: the change becomes a `PendingEdit` (only the changed fields, plus a
snapshot of what they were editing against). Saving again before review
updates the same pending edit; the edit form pre-fills it. The author can
withdraw it while it is still pending.

Admins and editors *without* the flag review the queue at
`/admin/pending_edits` (sidebar **Pending Edits**, badged with the count). Each
edit shows a word-level diff (removed words struck through in red, added words
in green) plus a side-by-side view. A warning appears when the live text
changed after the edit was submitted. **Approve & publish** applies the change
(the PaperTrail version is attributed to the author). **Reject** discards it.
Both accept an optional note to the author. Restricted editors see their own
edits (pending/approved/rejected, with reviewer notes) under **My Edits**.
The flag is ignored for admins. AI actions (rerun/refine/activate/archive,
analysis overrides) are not gated.

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
filterable by model type or user. The article page (`/admin/articles/:id`)
also has an **Edit history** timeline across all of that article's rewrites and
translations: word diffs of each manual change plus edit-approval proposals
(with reviewer and note); AI/system changes are hidden unless toggled on.

| Route | Description |
|---|---|
| `/admin` | Dashboard — counts and recent activity |
| `/admin/feeds` | Manage RSS feeds *(admin-only)* |
| `/admin/articles` | Browse articles, trigger rewrite |
| `/admin/rewrites` | View/edit rewrites, activate versions, edit history |
| `/admin/translations` | View/edit translations, post to Telegram, flag for manual edit, edit history |
| `/admin/telegram_channels` | Manage channels on any Telegram-compatible provider (provider, API URL, token, enable, autopost) *(admin-only)* |
| `/admin/telegram_posts` | Channel posts: **Scheduled** tab (each channel's queue in delivery order with estimated send windows) and **History** tab (posted/failed posts, filter by status/channel); click a post for details |
| `/admin/ollama_servers` | Manage Ollama servers and their model lists *(admin-only)* |
| `/admin/tasks` | Task queue — status/kind filters, request/response inspector, retry |
| `/admin/pending_edits` | Review queue for edits by editors flagged "Edits need approval" — diff, approve, reject (restricted editors see their own as **My Edits**) |
| `/admin/skip_phrases` | Phrases (matched against entry title or URL, case-insensitive) that make feed ingestion skip an entry *(admin-only)* |
| `/admin/users` | Manage admin/editor accounts *(admin-only)* |
| `/admin/activity_logs` | System-wide audit log of who changed what *(admin-only)* |

### AI bias / fact analysis

Every newly ingested article also gets an `analyze` task, running in parallel
with its rewrite (nothing waits for it). It scores the **original** article for
political leaning (Left / Center / Right %, summing to 100) and for how much of
it reports things that already happened vs. speculation about the future
(Fact / Spec %, summing to 100), plus a short reasoning sentence. Display only:
the scores never change the pipeline or autoposting.

- Shown as badges on the articles and translations lists, the translation
  show/edit pages, and in the Telegram admin-bot notification.
- Editable on the article page (**AI analysis** card). The card also has a
  **Re-analyze** button. Each split must add up to 100.
- The prompt is the editable `analyze` prompt (`/admin/prompts`). It runs on
  the first configured **rewrite** model.
- To backfill existing articles, use **⚖ Analyze unanalyzed** on the articles
  page, the bulk **Analyze** action, or `bin/rails bbc:analyze`. This needs
  migration `20261015000001`.

### Multi-server comparison

Each article's show page has two collapsible panels — **Run Rewrites on Targets** and **Run Translations on Targets** — that display every enabled server and its configured models as checkboxes. Selecting multiple server/model combos and clicking submit creates one task per selection. All results appear on the same page so you can compare outputs and activate the best version for posting.

---

## Outgoing Mail (Resend)

Password reset emails are the only mail this app sends, delivered through
[Resend](https://resend.com)'s SMTP relay (`smtp.resend.com`) via
`ActionMailer`'s built-in `:smtp` delivery method — no extra gem required.

1. Create a Resend account, verify a sending domain, and grab an API key.
2. Set the `resend_api_key` and `sender_email` credentials (see
   `app/services/mailer_config.rb`).
3. Set the `app_base_url` credential (the same value used for llmarkt
   webhooks) so reset links point at the right host.

Without `resend_api_key`/`sender_email` configured, `perform_deliveries`
is off (see `config/initializers/action_mailer.rb`) — the forgot-password flow
still runs end to end, it just doesn't actually send anything. In tests,
`config/environments/test.rb` sets the `:test` delivery method, so specs
assert against `ActionMailer::Base.deliveries` instead of hitting the network.

---

## Error Tracking (Sentry)

Every `rescue` in the app — not just exceptions that go unhandled — reports to
[Sentry](https://sentry.io) via `Sentry.capture_exception`, in addition to
whatever the site already did (log, retry, fall back). This covers both the
Rails app and the standalone worker (`worker/worker.rb`).

1. Create a Sentry project and grab its DSN.
2. Set the `sentry_dsn` credential (see `app/services/sentry_config.rb`).
   For the worker, set `SENTRY_DSN` in
   its own environment or `worker/.env` (see `worker/README.md`) — it does not
   read Rails credentials.

Without a DSN configured, `Sentry.init` is never called
(`config/initializers/sentry.rb` / the worker's own inline check), and every
`Sentry.capture_exception` call throughout the app is a documented no-op — the
app behaves exactly as it did before Sentry was added.

---

## Docker / Kamal Deployment

Production runs on **PostgreSQL**. The connection comes entirely from the
`database_url` credential (Solid Cache shares the same database — no
separate cache database). On boot the entrypoint runs `bin/rails db:prepare`,
which creates the schema (app tables + `solid_cache_entries`) on first deploy.
On later deploys it runs any pending migrations instead. Note that a fresh
`db:prepare` loads `db/schema.rb` and marks every migration as run without
executing it, so `schema.rb` must always match the migrations. Migration
`20261003000003` repairs databases built while `schema.rb` was missing the
`telegram_posts` unique index (it does nothing where the index already exists).

Build and run with Docker:

```bash
docker build -t khabarestan .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=$(cat config/master.key) \
  --name khabarestan khabarestan
```

`RAILS_MASTER_KEY` is the only value the container needs. Everything else
(`database_url`, `worker_api_token`, `admin_*`, …) comes from the encrypted
credentials baked into the image. Run `bin/rails bbc:credentials` (with
`RAILS_ENV=production`) to verify nothing is missing.

The `admin_*` credentials only matter on the very first
boot — the entrypoint runs `db:seed`, which creates that one admin account if
the `users` table is empty. After that, manage accounts at `/admin/users`.

> The web container does **not** need to reach Ollama. Run the
> [worker client](worker/README.md) separately (e.g. on the GPU host) with the
> `WORKER_API_TOKEN` set to the app's `worker_api_token` credential and
> `APP_URL` pointed at this app.

For Kamal deployments, see `.kamal/`. `RAILS_MASTER_KEY` is the only app
secret wired into `config/deploy.yml` / `.kamal/secrets`. `database_url`,
`worker_api_token` and the rest live in the encrypted credentials. A managed
Postgres just needs the `database_url` credential. To self-host Postgres on a
server, see the commented `accessories: db:` block in `config/deploy.yml`.

---

## Running Tests

```bash
bin/rails test
```
