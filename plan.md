# bbcfarsi Rails App — Plan

## Goal
Convert the `update.rb` script into a full Rails 8 admin web app.

## Architecture

### Models
| Model | Key fields |
|---|---|
| `Feed` | name, url, category, enabled |
| `Article` | feed, title, url (unique), description, published_at, status |
| `Rewrite` | article, content, model_name, status, error_message |
| `Translation` | rewrite, article, translated_title, translated_body, model_name, prompt_name, status, error_message |
| `TelegramChannel` | name, token, channel_id, enabled, autopost |
| `TelegramPost` | translation, telegram_channel, posted_at, status, error_message |

### Services
- `BbcFeedFetcher` — HTTParty + Feedjira, returns array of article hashes
- `FeedIngestor` — fetch enabled feeds, upsert Articles, enqueue rewrite Tasks
- `Autoposter` — post active completed Translations to autopost channels
- `ArticleRewriter` / `ArticleTranslator` / `TranslationRefiner` — build LLM chat
  `requests` and `process(responses)`; prompt logic only, no Ollama calls
- `OllamaClient` — builds the admin "debug curl" command (display only)
- `TelegramPoster` — sends translated message to a channel

### Task queue (replaces the background job system)
The Rails app does **no** LLM work and never calls Ollama. Instead it creates
`Task` rows (kind: rewrite / translate / refine). A separate **worker client**
(`worker/worker.rb`, runs where Ollama lives) claims tasks over a protected API,
calls Ollama, and posts results back.

- `Task` — DB-backed queue; polymorphic `target` (Rewrite or Translation);
  lifecycle `pending → claimed → completed/failed`; holds model, server URL, and
  chat `requests`. `complete!` chains the next task (rewrite → translate →
  autopost).
- Worker API (bearer `WORKER_API_TOKEN`): `GET /api/tasks/next`,
  `POST /api/tasks/:id/complete`, `POST /api/tasks/:id/fail`.

### Periodic work (no in-app scheduler)
Driven by an external scheduler (system cron) or the admin UI:
- `bin/rails bbc:fetch` (or the admin "Fetch now" button) — `FeedIngestor.run`
- `bin/rails bbc:autopost` — `Autoposter.run_all`

### Admin (HTTP Basic Auth)
- `/admin` — dashboard (counts, recent activity)
- `/admin/feeds` — CRUD, enable/disable toggle
- `/admin/articles` — list (filter by feed/status), show, trigger rewrite
- `/admin/rewrites` — list, show, edit content, rerun
- `/admin/translations` — list, show, edit title/body, post to channel, enable autopost
- `/admin/telegram_channels` — CRUD, enable/disable, autopost toggle

### Tech Stack
- Rails 8, SQLite3
- DB-backed `Task` queue + external worker client (LLM work)
- Solid Cache (Rails.cache only)
- Bootstrap 5 CDN (admin UI)
- dotenv-rails (.env loading)
- feedjira + httparty (RSS)
- Ollama via the standalone worker (stdlib net/http — no gem in the app)
- telegram-bot-ruby (Telegram)

## Status
- [x] Rails app init
- [x] Gemfile + bundle
- [x] Migrations + models
- [x] Services
- [x] Jobs
- [x] Routes + controllers + views
- [x] Solid Queue cron config
- [x] CHANGELOG update
- [x] README rewrite with full Ollama setup section
- [x] Multi-server / multi-model comparison: OllamaServer model + CRUD, multi_rewrite / multi_translate article actions, server+model labels on cards, jobs accept server_id/model kwargs, services accept server/model params
- [x] Fix /admin/jobs: add solid_queue adapter in development.rb so jobs are visible; override MissionControl layout with admin sidebar wrapper
- [x] Translate without rewrite: `Article#original_rewrite!` pass-through rewrite (no migration), `translate_original` action + button, "Original" option in multi-translate dropdown, single translate falls back to original
- [x] Process jobs in development: multi-db dev (`primary` + `queue`), `solid_queue.connects_to`, loaded `db/queue_schema.rb` into `storage/development_queue.sqlite3`, `bin/dev` sets `SOLID_QUEUE_IN_PUMA=true` (supervisor in-Puma); README + Background Jobs docs updated
- [x] **Replace the job queue with a pull-based task queue + external worker**: removed Solid Queue / Mission Control / all jobs / `ollama-ai` gem / `queue` db; added `Task` model, protected `/api/tasks` endpoints (`WORKER_API_TOKEN`), `worker/worker.rb` (stdlib-only client), `FeedIngestor` + `Autoposter` services, `bbc:fetch` / `bbc:autopost` rake tasks, and an admin `/admin/tasks` queue UI. Services became request-builders + result-processors. Tests updated (FeedIngestor, ArticleRewriter, Task, Api::Tasks). 78 tests green.
- [x] **Worker reads `worker/.env`**: `worker.rb` loads a `.env` file next to the script on startup via a stdlib-only `load_dotenv` parser (no gem); supports comments, `export` prefix, and quoted values; real env vars take precedence. README updated.
- [x] **Task Queue kind filter + numbered pagination**: `/admin/tasks` now filters by kind (composes with the status filter, active button highlighted, live counts); shared pagination partial renders numbered pages via `pagy.series` with `…` gaps and preserves active query-param filters across page links. Added `Admin::TasksControllerTest`. 82 tests green.
- [x] **Cross-filtered task counts**: status badges show `filtered/total` when a kind is selected and kind badges show `filtered/total` when a status is selected (`@status_counts_in_kind` / `@kind_counts_in_status`); plain totals when no cross filter is active. 84 tests green.
- [x] **Task priority**: new `priority` column (migration `20260608000001`, default 0); `Task.claim_next!` claims by `priority DESC, created_at ASC` (`by_priority` scope); admin ▲/▼ steppers on the queue + show page (`prioritize` action → `Task#reprioritize!`). Worker code unchanged (it calls `claim_next!`). 88 tests green. NOTE: dev/prod DBs still need `bin/rails db:migrate` (not run here per project rules).
- [x] **Task search + bulk priority + stale reclaim**: queue search by target article text (polymorphic-safe), composes with filters & pagination; bulk Raise/Lower/Set priority over checkbox-selected tasks (`bulk_prioritize`, form-attribute association, select-all JS); claimed tasks idle > `Task::STALE_AFTER` (1h) auto-return to pending via `reclaim_stale!` (folded into `claim_next!` + `bbc:reclaim_stale` rake task). 95 tests green.
- [x] **Toggle status/kind filters**: clicking the active status/kind button clears it (back to all); inactive sets it; removed the redundant "All" buttons; active buttons get `aria-pressed`. Filters still compose and preserve the search query. 96 tests green.
- [x] **Translations index filter + sort**: `/admin/translations` gains search (article + Persian title), status/model/active/archived filters, and clickable sortable column headers (asc/desc toggle, ▲/▼ indicator, whitelisted `SORT_COLUMNS` + `Arel.sql`). Sort preserves filters & resets page; filter form preserves sort; `eager_load(:article)` for join-based filter/sort. New `Admin::TranslationsHelper#translation_sort_link`. 106 tests green.
- [x] **Rewrite from translation page**: `/admin/translations/:id` adds a "Rewrite article" button that enqueues a rewrite task for the translation's article (reuses the articles `rewrite` action). 108 tests green.
- [x] **Unified Task-style filters**: Articles/Rewrites/Translations now use toggle filter buttons + count badges + search like the Task Queue, via three shared partials (`_filter_group`, `_filter_toggle`, `_filter_search`) that build links with `url_for(request.query_parameters…)` (compose, preserve sort/search, reset page). Tasks refactored onto the same partials. Controllers compute per-dimension counts. Added Articles + Rewrites controller tests. 119 tests green.
