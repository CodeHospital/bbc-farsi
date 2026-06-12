# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added — Post to Telegram dropdown on article show page
- Each completed translation card on `/admin/articles/:id` now has a card footer
  with a channel `<select>` dropdown and a "📤 Post" button, so an operator can
  post directly from the article page without navigating to the translation page.
- Channels already posted to show a "✓" prefix in the dropdown.
- `TranslationsController#post_to_channel` redirects use `redirect_back` (fallback:
  translation show page), so the action works from any originating page.
- `ArticlesController#show` now loads `@telegram_channels` and
  `@posted_channel_ids_by_translation` (single SQL batch query) for the card footer.
- 139 tests green.

### Added — Posted-article strikethrough + "Hide posted" filter on all content listings
- Article titles in every content listing show a strikethrough with dimmed opacity
  (`posted-title` CSS class) when the article's status is `"posted"` (i.e. it has
  been sent to Telegram), making it immediately obvious which articles are done.
  Covers: Articles, Rewrites, Translations, and Tasks index views.
- Added a **"Hide posted"** toggle filter to Articles, Rewrites, and Translations
  index pages (renders via the shared `filter_toggle` partial, composes with all
  existing filters and sort state).
  - Articles: `where.not(status: "posted")`
  - Rewrites / Translations: `where.not(articles: { status: "posted" })` (uses the
    existing `eager_load(:article)` JOIN — no extra query).
- 139 tests green.

### Added — Sortable columns on all listing pages
- All admin listing pages now have clickable, toggle-direction column headers:
  - **Articles**: Title, Feed, Published, Status (default: newest first)
  - **Rewrites**: Article, Model, Status, Created (default: newest first)
  - **Tasks**: Priority, Kind, Status, Attempts, Created (default: priority desc)
  - **Translations**: Article, Persian Title, Model, Active, Status, Created (unchanged)
  - **Feeds**: Name, Category, Status (default: name asc)
  - **Telegram Channels**: Name, Enabled, Autopost (default: name asc)
  - **Telegram Posts**: Channel, Status, Posted at (default: newest first)
  - **Ollama Servers**: Name, Status (default: name asc)
- Added generic `sort_link(column, label)` helper in `ApplicationHelper`; replaces
  the translations-specific `translation_sort_link` which has been removed from
  `Admin::TranslationsHelper`.
- Sort state (column + direction ▲/▼) is preserved across filter and search
  interactions; pagination is reset on sort change.
- Articles controller switches `includes(:feed)` → `eager_load(:feed)` to support
  JOIN-based sorting on `feeds.name`.
- Telegram Posts controller switches to `eager_load(:telegram_channel)` for
  channel-name sorting.
- 133 tests green.

### Changed — Worker is now a standalone Bundler app
- Added `worker/Gemfile` (Ruby ~> 3.3, `dotenv ~> 3.0`) making the worker an
  independent Bundler project with its own dependency manifest and lock file.
- Replaced the hand-rolled stdlib `load_dotenv` parser in `worker.rb` with the
  `dotenv` gem (`Dotenv.load`); behaviour is identical but more robust.
- Worker entry point updated to `bundle exec ruby worker.rb` (run from
  `worker/` directory).
- Updated `worker/README.md` to reflect new run command and gem requirement.

### Added — Worker model-aware task claiming
- **Worker** calls `GET /api/tags` on Ollama at startup of each poll cycle to
  discover locally available models (equivalent to `ollama list`), then passes
  them as `models[]` query params to `GET /api/tasks/next`.
- **`Task.claim_next!`** accepts an optional `models:` array; when present it
  filters pending tasks to those whose `model` is in the list, so a worker only
  ever claims tasks it can actually run. No models passed → any task is eligible
  (existing behaviour preserved).
- **`Api::TasksController#claim`** reads `params[:models]` and forwards to
  `claim_next!`; returns 204 (queue empty / no compatible tasks) when no match.
- Worker logs available models once per poll cycle; empty/unreachable Ollama
  falls back to "accept any task" gracefully.
- 125 tests green (6 new tests covering model-filter paths).

### Changed — PostgreSQL in production (via `DATABASE_URL`)
- Production now runs on **PostgreSQL**, configured entirely from the
  `DATABASE_URL` environment variable; development and test stay on SQLite.
- Gemfile: `pg` moved into a new `:production` group, `sqlite3` into
  `:development, :test`. Lockfile updated (pg 1.6.3).
- `config/database.yml`: production `primary` uses `adapter: postgresql` +
  `url: <%= ENV["DATABASE_URL"] %>`. The separate sqlite `cache` database was
  removed — **Solid Cache now lives in the primary database** (`config/cache.yml`
  production no longer sets `database:`).
- Solid Cache schema moved into the primary DB: new migration
  `20260609000001_create_solid_cache_entries` (+ `solid_cache_entries` in
  `db/schema.rb`); deleted the now-unused `db/cache_schema.rb`. **Run
  `bin/rails db:migrate`** on existing databases (the Docker entrypoint's
  `db:prepare` handles fresh production deploys).
- `Dockerfile`: install `postgresql-client` + `libpq-dev` (drop `sqlite3`),
  `BUNDLE_WITHOUT="development test"` so production installs `pg`, not `sqlite3`.
- `config/deploy.yml` + `.kamal/secrets`: `DATABASE_URL` wired as a Kamal secret;
  storage-volume comment updated; commented accessory example switched from MySQL
  to PostgreSQL. Documented in README and `.env.example`.

### Changed — Unified Task-style filters across Articles, Rewrites, Translations
- The Articles, Rewrites, and Translations index filters now match the Task
  Queue: **toggle filter buttons with live count badges** (click the active one
  to clear it) plus a **search box**, replacing the old dropdown/checkbox filter
  forms.
- Three reusable partials drive every filtered index:
  `admin/shared/_filter_group` (multi-value toggle buttons with optional
  `filtered/total` cross-counts and per-value badge colors),
  `admin/shared/_filter_toggle` (single on/off filter, e.g. "Show archived",
  "Active only"), and `admin/shared/_filter_search` (search box that preserves
  every other active filter/sort as hidden fields). Links are built with
  `url_for(request.query_parameters …)` so they compose, preserve sort/search,
  and reset pagination automatically. The Task Queue was refactored onto these
  same partials.
- **Articles**: status + feed toggle groups (with counts), "Show archived"
  toggle, title/description search. **Rewrites**: status toggle group, "Show
  archived" toggle, article-title/content search (now `eager_load(:article)`).
  **Translations**: status + model toggle groups, "Active only"/"Show archived"
  toggles, search — sortable columns unchanged. Controllers compute the
  per-dimension count hashes.
- Added `Admin::ArticlesControllerTest` and `Admin::RewritesControllerTest`
  (filter, search, archived-toggle, toggle-off coverage).

### Added — Request a rewrite from the translation page
- The translation detail page (`/admin/translations/:id`) now has a **"Rewrite
  article"** button that enqueues a fresh rewrite task for the translation's
  article (reusing the existing article `rewrite` action / `OllamaServer.pick`).
  Shown only when the translation has an article.

### Added — Translations index is filterable and sortable
- **Filters** on `/admin/translations`: free-text search (article title +
  Persian translated title), status, model (dropdown of distinct models), an
  "Active only" toggle, and the existing "Show archived" toggle. A "Clear" link
  appears when any filter is active.
- **Sortable columns.** Article, Persian Title, Model, Active, Status, and
  Created headers are clickable; each click toggles asc/desc and shows a ▲/▼
  indicator. Sorting is whitelisted to known columns (`SORT_COLUMNS`) and wrapped
  in `Arel.sql`; created-desc is the default and the stable tiebreaker.
- Sort links preserve active filters/search (and reset pagination); the filter
  form preserves the active sort via hidden fields. Article-column filtering and
  sorting use `eager_load(:article)` (single LEFT JOIN, no N+1). New
  `Admin::TranslationsHelper#translation_sort_link`.

### Changed — Task Queue status/kind filters are now toggles
- Clicking the **active** status or kind button clears that filter (returns to
  "all"); clicking an inactive one sets it. The redundant per-row "All" buttons
  were removed — toggling the active button off is the way to clear. Active
  buttons carry `aria-pressed="true"`. Filters still compose with each other and
  preserve the search query.

### Added — Task search, bulk priority, and stale-task reclaim
- **Search the queue by article text.** The Task Queue (`/admin/tasks`) has a
  free-text search that matches the target article's title/description. Because a
  task's `target` is polymorphic (Rewrite or Translation), the controller
  resolves matching article ids, then the rewrite/translation ids that point at
  them. Search composes with the status/kind filters and is preserved across
  filter links and pagination.
- **Bulk priority changes.** Row checkboxes + a select-all header let the admin
  pick many tasks and **Raise**/**Lower** their priority or **set an exact
  value** in one action (`PATCH /admin/tasks/bulk_prioritize`). Checkboxes are
  associated with the bulk form via the HTML `form=` attribute (no nested forms),
  and a small inline script drives select-all and the live selected-count.
- **Stale claimed tasks return to the queue.** A claimed task whose worker
  hasn't reported back within `Task::STALE_AFTER` (1 hour) is presumed dead and
  requeued to `pending`. `Task.claim_next!` reclaims stale tasks on every worker
  poll (self-healing), and `bin/rails bbc:reclaim_stale` (new rake task) covers
  the case where no worker is polling. Added a `(status, claimed_at)`-friendly
  `stale` scope and `reclaim_stale!`.
- Confirmed: **higher-priority tasks are claimed first** — `claim_next!` orders
  by `priority DESC, created_at ASC`.

### Added — Task priority
- **Admin can prioritize tasks.** New `priority` integer column on `tasks`
  (default `0`). The Task Queue (`/admin/tasks`) and the task detail page show a
  priority value with ▲/▼ steppers; raising a task's priority makes the worker
  claim it sooner. Steppers appear only while a task can still be claimed
  (pending or failed).
- **Worker claims by priority.** `Task.claim_next!` now orders by
  `priority DESC, created_at ASC` (new `by_priority` scope) instead of plain
  FIFO, so higher-priority tasks jump the queue while ties stay first-in-first-out.
  The queue list is ordered highest-priority-first, newest-first within a tier.
- New `PATCH /admin/tasks/:id/prioritize?direction=up|down` action backed by
  `Task#reprioritize!`; `priority` is validated as an integer.
- Migration `20260608000001_add_priority_to_tasks` adds the column plus a
  `(status, priority, created_at)` index for the claim lookup. **Run
  `bin/rails db:migrate` to apply it to your dev/prod databases.**
- Tests: claim-by-priority ordering, `reprioritize!` stepping, the `prioritize`
  controller action, and the index priority controls.

### Added — Task Queue kind filter + numbered pagination
- **Task Queue (`/admin/tasks`) is now filterable by kind** (rewrite / translate /
  refine) alongside the existing status filter. The two filters compose — picking
  a kind keeps the active status and vice versa — and the active button is
  highlighted. Each kind button shows a live count (`@kind_counts`).
- **Cross-filtered counts.** When a kind is selected, each status badge shows
  `filtered/total` (matching tasks of that kind / all tasks with that status);
  symmetrically, when a status is selected the kind badges show `filtered/total`.
  With no cross filter active, badges show the plain total.
- **Numbered pagination.** The shared pagination partial
  (`app/views/admin/shared/_pagination.html.erb`) now renders the page numbers
  between « and » (via `pagy.series`, with `…` gaps) instead of just a
  "Page X / Y" label.
- **Pagination preserves active filters.** Page links now carry the current query
  parameters (`status`, `kind`, search, etc.) forward, so paging through a
  filtered list no longer resets the filter. Fixes a latent issue affecting all
  paginated admin index pages (articles, rewrites, translations, telegram posts).
- Added `Admin::TasksControllerTest` covering kind filtering, combined
  kind+status filtering, and filter-preserving pagination.

### Added — Worker `.env` loading
- `worker/worker.rb` now loads configuration from a `.env` file sitting next to
  the script before reading its environment variables. Implemented with a small
  stdlib-only parser (`load_dotenv`) — no `dotenv` gem, keeping the worker
  dependency-free. Supports `#` comments, blank lines, an optional `export`
  prefix, and quoted values. Real environment variables take precedence over
  file values. Documented in `worker/README.md`.

### Changed — Replace the background job queue with a pull-based task queue + external worker
- **Removed the entire in-app job queue.** Deleted Solid Queue, Mission Control
  (`/admin/jobs`), and all five Active Job classes (`FetchFeedsJob`,
  `RewriteArticleJob`, `TranslateArticleJob`, `RefineTranslationJob`,
  `AutopostJob`). Removed the `solid_queue` and `mission_control-jobs` gems, the
  `queue` database (dev + prod), `config/recurring.yml`, `config/queue.yml`,
  `bin/jobs`, the `solid_queue` Puma plugin, and the `SOLID_QUEUE_IN_PUMA`
  wiring. The Rails app no longer depends on the `ollama-ai` gem and never calls
  Ollama directly.
- **New `Task` model** — a database-backed queue of LLM work
  (`kind`: rewrite/translate/refine). Each task drives an already-created target
  record (Rewrite or Translation) through `pending → claimed → completed/failed`.
  Tasks carry the model, the selected server's Ollama URL, and a list of chat
  `requests` (`{ key, messages }`); prompt logic stays in the Rails services.
- **Separate worker client** (`worker/worker.rb`, stdlib-only Ruby) — runs where
  Ollama lives, claims tasks over a protected API, calls Ollama, and posts
  results back. See `worker/README.md`.
- **Protected task API** (bearer token `WORKER_API_TOKEN`):
  `GET /api/tasks/next`, `POST /api/tasks/:id/complete`, `POST /api/tasks/:id/fail`.
  Constant-time token check; `401` without a valid token.
- **Admin Tasks UI** (`/admin/tasks`) replaces the old Jobs dashboard — filter by
  status/kind, inspect a task's requests/responses, and retry failed tasks.
- Services refactored into request-builders + result-processors:
  `ArticleRewriter`, `ArticleTranslator`, `TranslationRefiner` now expose
  `.requests(...)` and `.process(responses)` (no Ollama calls). `<think>` block
  stripping moved into `.process`.
- **Non-LLM periodic work moved out of the queue:** new `FeedIngestor` and
  `Autoposter` services. Feed fetching runs synchronously from the admin
  "Fetch now" button; both are exposed as `bin/rails bbc:fetch` and
  `bin/rails bbc:autopost` rake tasks for an external scheduler (system cron).
  A completed translate task still auto-posts inline (chaining preserved).
- Admin controllers now create `Task` records instead of enqueuing jobs; rerun /
  refine / multi-target actions create tasks.
- Tests: replaced the Active Job test with `FeedIngestorTest`; rewrote
  `ArticleRewriterTest` for the new interface; added `TaskTest` and
  `Api::TasksControllerTest`.

### Added
- Translate articles directly without a rewrite: new "Translate original (no rewrite)" action on the article page and an "Original article (no rewrite)" option in the multi-translate source dropdown. Implemented via `Article#original_rewrite!`, a pass-through rewrite holding the article's own text (`llm_model: "original"`), so the `translations.rewrite_id` NOT NULL constraint is satisfied with no schema change. The single-target "Translate" action also falls back to the original when no completed rewrite exists. Pass-through rewrites are hidden from the Rewrites list.

### Fixed
- Translation show page (`/admin/translations/:id`): added a link back to the source article
- Jobs page (`/admin/jobs`) now shows queued jobs in development: development now uses Solid Queue (`config.active_job.queue_adapter = :solid_queue` + `solid_queue.connects_to` a dedicated `queue` database, mirroring production), previously defaulted to in-memory `:async` which MissionControl cannot query
- Jobs page now uses the same admin sidebar layout as all other admin pages via a MissionControl layout override at `app/views/layouts/mission_control/jobs/application.html.erb`

### Changed — Development background jobs
- `config/database.yml` development is now multi-database (`primary` + `queue`), matching production; the queue store lives in `storage/development_queue.sqlite3` (loaded from `db/queue_schema.rb`)
- `bin/dev` sets `SOLID_QUEUE_IN_PUMA=true` so the Solid Queue supervisor/dispatcher/worker run inside Puma in development — jobs are both visible in `/admin/jobs` and processed without a separate `bin/jobs` process

### Added
- Job monitoring via Mission Control (`/admin/jobs`) — protected by existing admin session auth; linked in sidebar
- Articles index: free-text search field filters by title and description (persisted across filter resubmits)

### Fixed
- Translation show page: pass `server:` and `model:` to `ArticleTranslator.debug_curl_*` to fix 500 error; eager-load `ollama_server` in `set_translation`
- Rewrite show page: article title is now a clickable link to the article's admin page

### Changed — Remove hardcoded model constants
- Removed `REWRITE_MODELS`, `TRANSLATION_MODEL`, and `REFINE_MODELS` constants from all services — models are now exclusively sourced from `OllamaServer` records
- `model:` is now a required keyword on all service methods (`rewrite`, `translate`, `refine`) and all three jobs (`RewriteArticleJob`, `TranslateArticleJob`, `RefineTranslationJob`); jobs raise `ArgumentError` if called without a model
- Added `OllamaServer.pick(type)` — returns `[server, model]` for the first enabled server that has models of the given type; used by single-target dispatch in controllers and by `FetchFeedsJob`
- Single-target "Rewrite", "Translate", and "Refine" actions now call `OllamaServer.pick` and show an error flash if no server with relevant models is configured
- Rerun actions re-use the `ollama_server_id` and `llm_model` already stored on the original record
- `RewriteArticleJob` auto-chain prefers the same server's translate models; falls back to first available; skips silently if none configured (admin can trigger manually)
- `FetchFeedsJob` skips queueing rewrites if no servers are configured yet (no silent failures)

### Added — Multi-server / multi-model comparison
- **OllamaServer model** (`/admin/ollama_servers`) — admin can register multiple Ollama servers, each with independent lists of rewrite, translate, and refine models
- **Multi-target rewrite** — article show page has a collapsible "Run Rewrites on Targets" panel; each enabled server × model combo is a checkbox; submitting queues one `RewriteArticleJob` per selection (with `chain_translate: false` so the admin compares results before chaining)
- **Multi-target translate** — a parallel "Run Translations on Targets" panel lets the admin pick which completed rewrite to use and which server/model combos to translate on (`chain_autopost: false`); all results land on the same article page for side-by-side comparison
- **Server + model labels** on rewrite and translation cards — each card now shows the originating server name as a badge alongside the model name
- **Jobs accept `server_id:` and `model:` kwargs** (`RewriteArticleJob`, `TranslateArticleJob`, `RefineTranslationJob`) — existing single-target flows unchanged; `chain_translate`/`chain_autopost` flags control auto-chaining
- **Services accept `server:` and `model:`** (`ArticleRewriter`, `ArticleTranslator`, `TranslationRefiner`, `OllamaClient`) — all fall back to `OLLAMA_URL` env var when no server is supplied
- Fixed `TranslationRefiner#refine` — was referencing undefined `REFINE_MODEL` constant; now uses `REFINE_MODELS.first` via the `model:` kwarg
- **README rewrite** — full setup guide covering Ruby/Rails install, environment variables, database setup, Ollama installation and model pulls, background jobs, admin interface overview, and Docker/Kamal deployment
- Feed article count in feeds index is now a link that opens the articles list filtered by that feed
- **Double-click prevention** — global `turbo:submit-start` handler in the admin layout disables every submit button the moment its form is submitted (shows spinner); re-enables on Turbo error. Uses `cloneNode`/`appendChild` — no `innerHTML` — safe against XSS
- **Archive errors** — rewrites, translations, and articles now have an `archived` boolean. Error records show a 🗄 archive button; archived items are hidden from the default list views. Articles index has a "Show archived" checkbox filter. Archived articles can be unarchived from their show page



### Added — Version history and Persian text refinement
- Every rewrite and translation version is now stored and fully visible in the admin article view
- Active version is highlighted in green; all older versions remain accessible
- **"✓ Activate"** button on any rewrite or translation sets it as the preferred version for posting
- **"✦ Refine Persian"** button queues `RefineTranslationJob`, which runs the existing Persian text through `TranslationRefiner` (Qwen3 14B) to produce an improved Persian version stored as a new translation version
- New `TranslationRefiner` service with a Persian-specific editing system prompt
- `activate!` method on `Rewrite` and `Translation` deactivates all siblings for the same article, marking only one version as active at a time
- `AutopostJob` now only posts the **active** translation (not every completed one)
- `RewriteArticleJob` and `TranslateArticleJob` automatically activate each newly completed version
- Added `active` boolean column to `rewrites` and `translations` tables (default `false`)



### Added — Minitest suite
- 53 tests across models, services, jobs, and admin controllers
- Model tests: validations, uniqueness, scopes, `ignorable?`, `seed_bbc_feeds!` idempotency, `unposted_for` query
- Service tests: `BbcFeedFetcher` SSRF allowlist (scheme + host rejection), RSS parse + filter; `ArticleRewriter` `<think>` tag stripping; `TelegramPoster` message format
- Job tests: `FetchFeedsJob` enqueues `RewriteArticleJob` per new article, skips existing and disabled feeds
- Controller tests: HTTP Basic Auth required/rejected/accepted on all admin routes
- Added `webmock` + `minitest` gems to development/test group
- `config/initializers/required_env.rb` skips env-var check in test environment

### Added — Rails app conversion
- Full Rails 8 app with SQLite3, replacing the standalone `update.rb` script
- Six models: `Feed`, `Article`, `Rewrite`, `Translation`, `TelegramChannel`, `TelegramPost` with associations and status tracking
- Four services: `BbcFeedFetcher`, `OllamaClient`, `ArticleRewriter` (Qwen3 14B), `ArticleTranslator` (aya-expanse:32b), `TelegramPoster`
- Four background jobs via Solid Queue: `FetchFeedsJob`, `RewriteArticleJob`, `TranslateArticleJob`, `AutopostJob`
- Admin panel at `/admin` (HTTP Basic Auth) with Bootstrap 5.3.8 and Bootstrap Icons 1.13.1 (all CDN resources protected with SRI hashes)
- Admin sections: Dashboard, Feeds (enable/disable), Articles (filter, trigger rewrite/translate), Rewrites (edit + rerun), Translations (edit, manual post to any channel, rerun), Telegram Channels (CRUD, autopost toggle), Telegram Posts (history)
- Multiple Telegram channel support with per-channel autopost setting
- Solid Queue recurring tasks: fetch feeds every 30 min, autopost every 5 min
- `db/seeds.rb` seeds all 7 BBC RSS feeds automatically (`bin/rails db:seed`)
- `plan.md` documents full architecture



### Changed
- Added Qwen3 14B rewrite step before translation: each article body is rewritten/explained in plain English before being translated to Persian
- Extracted all logic into focused methods (`parse_feed_entries`, `skip_article?`, `rewrite_description`, `translate_and_post`, `post_to_telegram`, etc.) to satisfy RuboCop method/block length limits
- Promoted `db`, `bot`, `prompts` to instance variables for cleaner method signatures
- Extracted `multi_mode?` and `log_skip` helpers; fixed all `Layout/LineLength` and `Style/IfUnlessModifier` offenses
- Replaced `news-api` gem with `feedjira` + `httparty` for fetching BBC news directly from RSS feeds
- Added all seven BBC RSS feeds: top, world, uk, business, technology, science, health
- Extracted article fetching into `fetch_bbc_articles` method with per-feed error handling
- Removed `NEWS_API_KEY` requirement — no API key needed, feeds are public
- Articles are now deduplicated by URL across all feeds before processing
- Dropped image posting (BBC RSS feeds do not reliably include `urlToImage`); all messages sent as text
- Removed the `content == description` skip check (RSS entries have only `summary`)



### Changed
- Replaced OpenAI API with Ollama AI for local LLM inference
- Updated `update.rb` to use `ollama-ai` gem instead of `ruby-openai`
- Changed environment variable from `OPENAI_API_KEY` to `OLLAMA_URL` and `OLLAMA_MODEL`
- Updated API client initialization to use Ollama.new with local server address
- Modified chat completion call to use Ollama's chat method with compatible parameters
- Updated `.env.example` to include Ollama configuration variables
- Updated `readme.md` to reflect Ollama AI usage and setup instructions
- Updated `Dockerfile` to install `ollama-ai` gem instead of `httparty`
- Removed `OPENAI_API_KEY` from required environment variables (now using local Ollama)

### Fixed
- Added OpenSSL configuration to resolve "unable to get certificate CRL" SSL errors on macOS
- Configured certificate store to disable CRL checking for News API connections
