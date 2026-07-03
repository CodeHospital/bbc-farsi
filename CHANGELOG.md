# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added — Full NYT RSS catalog in the seed data

- `Feed::NYT_FEEDS` expanded from the curated 7-feed starter set to the complete catalog listed on https://www.nytimes.com/rss (74 feeds, verified reachable): World (+Africa/Americas/Asia Pacific/Europe/Middle East), U.S. (+Education/Politics/The Upshot), N.Y./Region, Business (+Energy & Environment/Small Business/Economy/DealBook/Media & Advertising/Your Money), Technology (+Personal Tech), Sports (+Baseball/College Basketball/College Football/Golf/Hockey/Pro Basketball/Pro Football/Soccer/Tennis), Science (+Space & Cosmos), Health (+Well Blog), Climate (+Weather), Arts (+Art & Design/Book Review/Dance/Movies/Music/Television/Theater/Lens Blog), Style (+Fashion & Style/Dining & Wine/Love/T Magazine), Travel, Marketplace (Jobs/Real Estate/Autos), Other (Obituaries/Times Wire/Most E-Mailed/Most Shared/Most Viewed), and all 14 Opinion columnists + Sunday Opinion. `db/seeds.rb`/`seed_nyt_feeds!`/the admin "Seed NYT Feeds" button are unchanged — they just now populate the full catalog instead of 7 feeds.
- The NYT `/rss` page's own "Travel" link (`www.nytimes.com/services/xml/rss/nyt/Travel.xml`) 301-redirects to `rss.nytimes.com`; since `FeedFetcher` fetches with `follow_redirects: false` (by design, for SSRF safety), used the canonical `rss.nytimes.com` URL directly instead. "Environment" (Science section) and "Climate" (Climate & Weather section) are the same feed on nytimes.com — kept once as "Climate" (a second hash entry with the same URL would just no-op in `seed_feeds!`, silently losing one of the two names).
- Added a `Feed` test asserting every `NYT_FEEDS` URL is unique and on an allowed NYT host; updated the seed-count tests to assert against `Feed::BBC_FEEDS.size`/`Feed::NYT_FEEDS.size` instead of hardcoded numbers so they don't need touching every time the catalog grows. 294 tests green (1 new).

### Added — Single-feed fetch with a new/updated/skipped-reason report

- `/admin/feeds` now has a per-row **Fetch** button (`POST /admin/feeds/:id/fetch`, `Admin::FeedsController#fetch`) that fetches just that one feed synchronously and re-renders the index with a "Fetch results" panel: New/Updated/Skipped badge counts, plus a table of every skipped entry with its title and reason (e.g. "already up to date", "title starts with ignored prefix \"Watch:\"", a validation error, or the raw fetch error if the request itself failed — shown as a failure banner instead of crashing the page).
- `FeedFetcher#fetch_with_report(feed)` (used only by this new path) parses the same entries as `#fetch` but returns every one, tagging ignored entries with `Article.ignore_reason` instead of silently dropping them; it never raises — allowlist/HTTP/parse failures come back as `error:` so the admin page can show a friendly banner. `#fetch` (used by the existing bulk `FeedIngestor.run` / `bbc:fetch`) is unchanged. `Article.ignore_reason(title, url)` is the new source of truth; `Article.ignorable?` is now defined in terms of it.
- `FeedIngestor.run_one(feed)` is the single-feed counterpart to `.run`: existing articles are now refreshed (`title`/`description`/`published_at`) when the feed entry changed — via Active Record's own dirty-tracking (`article.changed?`) rather than manual diffing — and are reported as "already up to date" when nothing changed. `.run` (bulk/automatic ingestion) is untouched: still create-only, still returns a plain integer count.
- Renamed the disallowed-host error text from the internal class name (`BbcFeedFetcher`/`NytFeedFetcher`) to a friendly `source_label` ("BBC"/"NYT") since it's now shown directly in the admin UI, not just logged.
- Added `Article` ignore-reason tests, `FeedFetcher#fetch_with_report` tests (ignored-with-reason, disallowed host as `error:`, HTTP error as `error:`), `FeedIngestor.run_one` tests (new+task, update, skip-unchanged, fetch error), and controller tests for the `fetch` action (success report + failure banner). 293 tests green (12 new). Smoke-tested live: fetching an intentionally-misconfigured feed showed "Failed: Feed URL ... is not an allowed BBC host"; fetching a real NYT feed showed "New: 20, Updated: 0, Skipped: 0", then re-fetching the same feed showed "New: 0, Updated: 0, Skipped: 20" with every row explained as "already up to date".

### Added — NYT feeds alongside BBC (migration `20260703000001`)

- Feeds now carry a `source` column (`"bbc"` / `"nyt"`, default `"bbc"`, validated against `Feed::SOURCES`) so the app can ingest more than one publisher.
- Extracted the shared RSS-fetching logic (host allowlist check, `Feedjira` parse, `Article.ignorable?` filtering, error rescue/logging) out of `BbcFeedFetcher` into a new `FeedFetcher` base class; `BbcFeedFetcher` and the new `NytFeedFetcher` (`allowed_hosts`: `rss.nytimes.com`, `www.nytimes.com`) are now thin subclasses that only declare their own allowlist.
- `Feed::NYT_FEEDS` mirrors `BBC_FEEDS`' categories (Top Stories, World, U.S., Business, Technology, Science, Health) pointing at the classic `rss.nytimes.com/services/xml/rss/nyt/*.xml` feeds (verified reachable). `Feed.seed_nyt_feeds!` seeds them (idempotent, same pattern as `seed_bbc_feeds!`); both now share a private `Feed.seed_feeds!(definitions, source:)` helper. `db/seeds.rb` seeds both sources.
- `FeedIngestor.run` now picks the fetcher per-feed via `FETCHER_CLASSES` keyed on `feed.source` (unknown/blank source falls back to `BbcFeedFetcher` for pre-migration rows) instead of hardcoding `BbcFeedFetcher` for every enabled feed.
- Admin `/admin/feeds`: added a "Seed NYT Feeds" button (`seed` action now reads `params[:source]`), a sortable Source column/badge, and a Source `<select>` (`Feed::SOURCES`) on the new/edit form so manually-added feeds can be routed to the right fetcher.
- Added `NytFeedFetcherTest` (mirrors `BbcFeedFetcherTest`: allowlist/scheme rejection, successful parse + `Article.ignorable?` filtering, HTTP-error swallowing), `Feed` model tests for `seed_nyt_feeds!`/source validation/default, and a `FeedIngestor` test asserting BBC vs. NYT feeds are routed to their respective fetcher. 281 tests green (10 new).
- NOTE: dev/prod DBs still need `bin/rails db:migrate` (not run here per project rules) before the `source` column and NYT routing take effect; until then all feeds behave as `source: "bbc"` via the in-memory default.

### Added — Bulk actions on Articles, Rewrites, and Translations listing pages

- `/admin/articles`, `/admin/rewrites`, and `/admin/translations` each gain a row-checkbox column, a "select all" header checkbox, and a bulk-action bar above the table (mirroring the existing Task Queue bulk-priority UI):
  - Articles: **Rewrite** (`bulk_rewrite`) and **Translate** (`bulk_translate`) — same server/model selection (`OllamaServer.pick`) and same rewrite-fallback logic (latest completed rewrite, else pass-through original) as the existing single-article actions.
  - Rewrites: **Rerun** (`bulk_rerun`) — re-queues a rewrite task per selected row using that row's own server/model, same as the single Rerun button.
  - Translations: **Retranslate** (`bulk_rerun`) and **Refine** (`bulk_refine`) — retranslate reuses each row's own server/model; refine uses `OllamaServer.pick(:refine)`.
  - All six new controller actions are POST collection routes; each redirects back with a notice/alert (empty selection or no configured server → alert).
- Extracted the per-page "select all + live counter" JavaScript (previously duplicated inline on the Tasks page) into one generic, data-attribute-driven function in the admin layout (`initBulkSelectGroups`): a `data-bulk-select-all="<group>"` checkbox drives any `.bulk-select[data-bulk-group="<group>"]` checkboxes and an optional `data-bulk-count="<group>"` counter. The Tasks page bulk-priority UI now runs on this shared script instead of its own copy (behavior unchanged).
- Each bulk form uses one `form_with` per page with per-button `formaction` (Turbo respects the HTML `formaction` attribute) so a single checkbox selection can be routed to different actions (e.g. Translations' Retranslate vs. Refine) without duplicating the checkbox list.
- Added controller test coverage for all six actions (selection required, server-required alerts, correct task counts created) plus a manual smoke test in the browser (login → select two articles → bulk Rewrite → notice + tasks created and visible on `/admin/tasks`). 271 tests green.

### Added — Task priority changes and retries are mirrored onto llmarkt

- Pulled the live spec from https://llmarkt.codehospital.com/api-docs and implemented the two job-management endpoints it exposes beyond job submission: `PATCH /jobs/{id}/priority` (signed delta, only while the job is still `pending` on their side) and `POST /jobs/{id}/retry` (requeues a `failed` job in place — same `job_id`). Added `LlmarktClient.update_job_priority(job_id, delta)` / `LlmarktClient.retry_job(job_id)`, with their own request/error tests in `llmarkt_client_test.rb`.
- Added `LlmarktSubmitter.update_priority(task, delta)` / `.retry_task(task)` — best-effort wrappers (same style as `submit_task`): no-op and return `false` when llmarkt is disabled, the task was never submitted there (`external_job_id` blank), or the remote call errors (e.g. the llmarkt-side job already moved past `pending`/`failed`); errors are logged, never raised.
- `Task#reprioritize!` now also calls `LlmarktSubmitter.update_priority` with the same ±1 delta after saving the local `priority` column, so both the single-task priority arrows and `Admin::TasksController#bulk_prioritize` (now iterating tasks via `reprioritize!`/computed per-task deltas instead of a raw `update_all`) push the change to llmarkt when applicable.
- Added `Task#retry!`: prefers requeuing the *same* llmarkt job in place (keeps `job_id`, keeps any responses already recorded for earlier steps in a chained request) when the task has an external job id and the retry call succeeds; falls back to the existing plain local `requeue!` (Ollama worker fallback) otherwise. `Admin::TasksController#retry` now calls this instead of `requeue!` directly.
- `Task#mark_claimed!` now also clears `error_message` (on both the task and its target) since it's reused by `retry!` to bring a task back to `claimed` after a successful llmarkt retry.
- Full suite green (259 runs, 0 failures) including new coverage in `task_test.rb`, `llmarkt_submitter_test.rb`, `llmarkt_client_test.rb`, and `tasks_controller_test.rb`.

### Added — Task list on the admin article show page

- The admin article show page (`/admin/articles/:id`) now has a **Tasks** section listing every `Task` targeting one of the article's rewrites/translations: id (linked to `admin_task_path`), kind, server/model, status badge, external llmarkt job id (or "—"), created-at, and a Retry/Cancel button for failed/pending tasks.
- `Admin::ArticlesController#show` now builds `@article_tasks` (all tasks, newest first) and derives `@task_by_target` from it, replacing the old single-purpose `queue_tasks_by_target` query (renamed `queue_tasks_for_article`) so both views share one query.
- Added controller tests: kind/status/external-job-id rendering, and the "—" placeholder when a task has no external job id yet.

### Added — Delete action for cached IP geolocations in admin

- `admin/ip_geolocations` now supports `DELETE` (route added as `only: %i[index destroy]`, `admin_ip_geolocation_path`). Each row in the index table has a "Delete" button (`turbo_confirm` prompt) that removes the cached `IpGeolocation` row and redirects back with a notice.

### Added — Paginated page views on the admin article show page

- `Article has_many :article_views, dependent: :destroy`. The admin article show page (`/admin/articles/:id`) now has a **Views** section below Translations: a paginated (30/page via the standard `Pagy::Method` + `admin/shared/pagination` partial), newest-first table of every recorded view with its viewed-at time, edition (FA/EN), country (flag + name), and city.
- Added controller/view tests covering: rendering country/city, the "No views recorded yet." empty state, and pagination kicking in past the first page.

### Added — `ArticleView` now stores country name, city name, and country code

- `article_views` gains `country_name` and `city_name` columns (migration `20260701000002_add_country_name_and_city_name_to_article_views`; `db/schema.rb` updated manually, version bumped to `2026_07_01_000002`, per project migration policy). The existing `country_code` column is kept (still used by the Analytics group-by) but is now *derived*, not fetched directly.
- `ArticleView.track!` now resolves an IP to `[country_name, city_name]` (via the `IpGeolocation` cache / geolocation service, unchanged) and derives `country_code` from the name via the new shared `Country.code_for_name` lookup, storing all three on the row.
- Extracted the ISO-code ⟷ name table (previously duplicated as `ApplicationHelper::COUNTRY_NAMES`) into a plain `Country` model/module (`app/models/country.rb`) with `Country.name_for(code)` / `Country.code_for_name(name)`, since it's now needed by both a model (`ArticleView`) and a view helper. `ApplicationHelper#country_name` / `#code_for_country_name` now delegate to it; behavior and the existing `application_helper_test.rb` coverage are unchanged.
- Full suite green (235 runs, 0 failures) after a manual smoke test confirming first-lookup vs. cache-hit paths both populate `country_name`/`city_name`/`country_code` correctly.

### Fixed — `ApplicationHelper#country_flag` reverse-lookup bug + full test coverage

- `country_flag` called a non-existent `Hash#get_code_by_value` and then discarded its result, always falling through to the 🌐 fallback for anything that wasn't already a 2-letter code — broken by the switch to storing full `country_name` values (e.g. `"United States"`) in the new IP-geolocation cache instead of 2-letter codes.
- Replaced with a real reverse lookup: `country_flag` now accepts either a 2-letter ISO code or a full country name (case-insensitive, whitespace-tolerant) and resolves it to the correct flag emoji via a new memoized `code_for_country_name` helper.
- Added `test/helpers/application_helper_test.rb`: full coverage of `country_flag`, `code_for_country_name`, `country_name`, and `sort_link` (23 tests) — codes vs. full names, case/whitespace handling, unknown/nil/blank inputs, and `sort_link`'s direction-toggle/indicator/query-param-preservation behavior. Full suite green (235 runs, 0 failures).

### Added — Local IP geolocation cache + admin listing

- New `ip_geolocations` table + `IpGeolocation` model: a local cache of IP → country lookups. `ArticleView.geolocate_ip` now checks this cache first and only calls the geolocation HTTP service on a cache miss, storing the result (including "no country" resolutions) so a given IP is fetched at most once. Cache hits bump a `lookups_count` and refresh `last_used_at` via a single `UPDATE` (no validations/callbacks). Concurrent first-lookups of the same IP are handled by rescuing `RecordNotUnique`.
- The HTTP call was extracted into `ArticleView.fetch_country_from_service`, which raises on transport/parse errors so a failed call is never cached as a spurious "no country" result.
- New admin page **IP Geolocations** (`/admin/ip_geolocations`, sidebar link): sortable, paginated table of every cached IP with its country (flag + name), lookup count, last-used and cached-at timestamps, plus an IP/country search box and summary cards (cached IPs, resolved-to-country, total lookups served).
- Migration `20260701000001_create_ip_geolocations`; `db/schema.rb` updated manually (version bumped to `2026_07_01_000001`) per project migration policy.

### Fixed — Worker status server `log` ArgumentError

- `handle_status_request` and `start_status_server` were calling `log(message)` with one argument, but `log` requires `level, message` — crashing the status-server thread with `ArgumentError: wrong number of arguments (given 1, expected 2)`. Changed both call sites to use the `error(msg)` convenience wrapper.

### Added — llmarkt webhook signature verification (X-Vibe-Signature)

- The llmarkt grid now signs every webhook with `X-Vibe-Signature: sha256=<HMAC-SHA256 of the raw body, keyed with the API key>`. `Api::LlmCallbacksController` now verifies this header (constant-time, `ActiveSupport::SecurityUtils.secure_compare`) **before** any processing and returns `401` on a missing/invalid/mismatched signature — so callbacks are authenticated both by the signed URL token (routing) and the HMAC (payload authenticity).
- `Llmarkt.webhook_signature` / `Llmarkt.valid_webhook_signature?` implement the HMAC; rejected when the API key is absent.
- Webhook tests extended: valid-signature path plus rejection for missing / wrong / body-mismatched signatures. 212 tests green.
- (Other endpoints in the updated API doc — blob upload, list/cancel/retry jobs, models, usage — were intentionally not implemented; this integration only submits jobs and receives webhooks.)

### Fixed — Worker status page missing after parallel-worker refactor

- The status HTTP server (`TCPServer` on `STATUS_PORT`, default 4567) was accidentally dropped when the worker was refactored to the parallel multi-worker edition; the implementation was replaced with placeholder comments.
- Restored the full status server — adapted for the new `CONFIG`/`STATE` structure: `CONFIG.status_bind/status_port/app_url/default_ollama_url/concurrency`, `snapshot[:active_tasks]` (keyed by worker id) instead of the old single `snapshot[:current]`, and `snapshot[:models_cache]` instead of the old flat models list.
- Status page now shows an **Active workers** table (one row per in-flight task) and the history table gains a **Worker** column.
- Both `/` and `/status.json` endpoints work again.

### Added — llmarkt (vibeearning) LLM Grid as the primary LLM backend (webhook-based)

- New integration that submits each enqueued `Task` to the **llmarkt** grid API (`llmarkt.codehospital.com`) and receives results via a **webhook**, replacing the polling Ollama worker as the *primary* execution path. The worker stays as a **fallback** for any task that can't be submitted.
- **`Llmarkt`** (`app/services/llmarkt.rb`) — config + signed-token helpers. Reads `llmarkt_api_url` / `llmarkt_api_key` / `app_base_url` (+ optional `llmarkt_model_match`) from **Rails credentials**, falling back to the `LLMARKT_API_URL` / `LLMARKT_API_KEY` / `APP_BASE_URL` / `LLMARKT_MODEL_MATCH` env vars. `enabled?` is true only when url + key + app base url are all present.
- **`LlmarktClient`** (`app/services/llmarkt_client.rb`) — thin HTTParty client for `POST {api_url}/jobs` (bearer auth, `model_match` default `family`), raising `LlmarktClient::Error` on any failure.
- **`LlmarktSubmitter`** (`app/services/llmarkt_submitter.rb`) — runs a Task's multi-step request chain one job at a time. Each job's `webhook_url` carries a tamper-proof signed token (`Rails.application.message_verifier("llmarkt")`) encoding the task id + request key, so the callback needs no other auth and no job-mapping table. `{{key}}` placeholders are substituted from earlier outputs; system+user messages are flattened into a single prompt. Out-of-order / duplicate callbacks are ignored.
- **`Api::LlmCallbacksController`** + route `POST /api/llm_callbacks` — public webhook (authenticated solely by the signed token, *not* the worker bearer). `completed` → record output and advance the chain (or `task.complete!`); `failed` → `task.fail!`; invalid token → 401; unknown task → 404.
- **Auto-submit on enqueue** — `Task#after_create_commit :submit_to_llmarkt` submits the task as soon as it's created. On success the task is marked `claimed` (the worker won't pick it up); if llmarkt is disabled or submission fails, the task is left `pending` for the worker fallback. Errors never break enqueue.
- **Schema** — migration `20260622000001` adds `tasks.external_job_id` (+ index) to track the in-flight llmarkt job id. NOTE: run `bin/rails db:migrate` on dev/prod (test DB prepared via `db:test:prepare`).
- `.env.example` documents the new (credentials-preferred) settings. 211 tests green (14 new across `LlmarktClient`, `LlmarktSubmitter`, and the webhook controller).

### Fixed — Unpublishing an article from the Farsi portal no longer removes it from the English portal

- "Unpublish from portal" on the article admin page previously called `Article#archive!` (setting `archived: true`), which hid the article from both the Farsi and English public portals.
- The action now archives the article's **translations** instead (`translations.update_all(archived: true)`). This removes it from the Farsi portal (which shows translations), while the article itself remains visible in the English edition (as an `ArticleStory`).
- "Republish to Farsi portal" correspondingly unarchives all translations (`update_all(archived: false)`).
- Button label updated to "Unpublish from Farsi portal" / "Republish to Farsi portal" to make the scope explicit.
- Button state now driven by `@farsi_portal_visible` (whether any non-archived completed translation exists) rather than `@article.archived?`.

### Fixed — Worker process exited after SHUTDOWN_GRACE × concurrency seconds

- The main thread was immediately calling `thread.join(15)` on every worker right after spawning them. After all timeouts expired (e.g. 30 s with 2 workers), the main thread exited and Ruby killed all worker threads mid-task with no log output.
- Fix: the main thread now loops `sleep(1) until $shutdown` to stay alive, and only enters the grace-period joins after a SIGINT/SIGTERM is received.

### Fixed — Worker shutdown now logs the reason it stopped

- `trigger_shutdown` gains a `reason:` keyword and logs `Shutdown triggered: <reason>` before interrupting threads, so the cause is always visible in the output.
- Signal traps pass the signal name: `SIGINT (Ctrl-C)` or `SIGTERM`.
- Each worker thread logs `Stopped — reason: <reason>` on exit instead of the bare `Stopped`.
- The `Interrupt` rescue in the worker loop records `$shutdown_reason` so threads report why they broke out.
- The `StandardError` rescue in the worker loop now logs a 5-line backtrace for easier root-cause diagnosis.
- `when 401` in `claim_and_run` replaced `abort` (which printed to STDERR unformatted and killed the process) with a proper `error(...)` log + `trigger_shutdown` + `raise Interrupt`, giving all threads a chance to clean up.
- The 401 `warn` for unexpected HTTP responses now includes the response body prefix for context.

### Added — Admin unpublish/republish for articles and translations

- **Article-level unpublish**: renamed the "Archive article" button on the article show page to **"Unpublish from portal"** / **"Republish to portal"** for clearer intent — the same `archived` flag that drives portal visibility is used.
- **Translation-level unpublish**: added **"Unpublish"** button (with confirmation) on every completed translation card in the article show page; unpublishing a translation hides it from the public portal while the previous (older, non-archived) translation is shown instead. An **"Unpublished"** badge with dimmed card styling marks affected cards.
- **Translation republish**: archived (unpublished) translations gain a **"Republish"** button on the article show page and a dismissible alert + button on the translation show page.
- `Translation#unarchive!` method added; `POST /admin/translations/:id/unarchive` route and `Admin::TranslationsController#unarchive` action wired up.
- Translations index: archived rows now display an **"Unpublished"** badge in the Active column and a muted `table-secondary` row style.
- 197 tests green.

### Fixed — Worker now terminates immediately on Ctrl-C / SIGTERM

- Signal traps now call `trigger_shutdown`, which sets `$shutdown = true` **and** raises `Interrupt` on every worker thread via `Thread#raise`. This interrupts threads blocked inside long Ollama HTTP calls (up to `OLLAMA_TIMEOUT` seconds) so the process exits without hanging.
- `claim_and_run` gains a `rescue Interrupt` clause that reports the in-flight task as failed to the Rails API (best-effort) before re-raising so the thread exits.
- The worker loop catches `Interrupt` with a clean `break` instead of logging it as an error.
- `$worker_threads` promoted from a local to a global so the signal trap can reach it.
- `Thread#join` is now called with a 15-second grace period (`SHUTDOWN_GRACE = 15`) — any thread still alive after that is abandoned and the process exits.

### Changed — Stale task reclaim window reduced to 15 minutes

- `Task::STALE_AFTER` changed from `1.hour` to `15.minutes`; claimed tasks not reported back within 15 minutes are automatically returned to `pending` status on the next `claim_next!` poll or `bbc:reclaim_stale` rake invocation.


### Fixed — Translator uses rewritten title + no placeholder brackets

- `ArticleTranslator.requests` now uses `rewrite.rewritten_title` (falling back to `rewrite.article.title` for older rewrites without one) as the title input, so the LLM translates the rewritten headline rather than the raw BBC original.
- Added rule 8 to `prompt`: the model is explicitly forbidden from inserting brackets, placeholders, or annotations (e.g. `[نام]`, `[اطلاعات ناقص]`) for missing information — it must translate only what is given and omit the rest.
- Output rule extended: "No brackets, placeholders, or annotations of any kind."
- 197 tests green.



### Added — Separate rewritten title and body from ArticleRewriter (migration `20260621000001`)

- `ArticleRewriter` now sends two sequential LLM requests instead of one: `body` (rewrite the article body from the original title + description) and `title` (rewrite the headline from the rewritten body, using a `{{body}}` placeholder that the worker substitutes at runtime).
- `ArticleRewriter.process` returns `{ rewritten_title:, content: }` instead of a plain string; `Task#complete!` for `"rewrite"` tasks uses `.merge(status:)` to store both fields, matching the translate/refine pattern.
- New `rewritten_title` string column on `rewrites` (migration `20260621000001`; run `bin/rails db:migrate` on dev/prod then `bin/rails bbc:backfill_slugs` is not needed here).
- Worker gains `{{key}}` placeholder substitution: each request's messages are scanned for `{{prior_key}}` patterns and replaced with the accumulated response before the Ollama call.
- Admin rewrite show page and article show page now display `rewritten_title` above the body when present.
- 197 tests green.



### Fixed — Retry button now uses Turbo Stream for in-place updates

- Changed `data: { turbo_stream: true }` to `data: { turbo: true }` on the "Retry" button in `_task.html.erb` so the POST request includes the proper Turbo Stream Accept header (`text/vnd.turbo-stream.html`), ensuring the response is handled by Turbo Stream instead of the HTML fallback route.

### Changed — Retry button on failed tasks uses Hotwire in-place update

- Clicking "Retry" on the `/admin/tasks?status=failed` page now updates only the affected table row via Turbo Stream — no page refresh or redirect.
- Extracted the task `<tr>` into `admin/tasks/_task.html.erb` (with `id: dom_id(task)`) so it can be re-rendered and swapped in by `retry.turbo_stream.erb`.
- `Admin::TasksController#retry` now responds to `turbo_stream` (inline row replace) as well as `html` (fallback redirect for non-Turbo requests).
- 14 tasks controller tests still green.

### Changed — Worker now runs N parallel threads (default 4)

- `WORKER_CONCURRENCY` env var (default `4`) controls how many worker threads run simultaneously. Each thread independently claims and processes tasks from the Rails queue.
- `WorkerState` refactored from single-task tracking to a `@active_tasks` hash keyed by `worker_id` (`"worker-1"` … `"worker-N"`). All public methods (`begin_task`, `set_current_request`, `finish_task`) now accept `worker_id:`.
- **Shared Ollama model cache with cooldown**: `claim_models_refresh?` atomically claims the refresh slot for one thread per `MODELS_REFRESH_INTERVAL` (30 s); all other threads reuse the cached model list, eliminating redundant `/api/tags` calls under concurrency.
- **Thread-safe logging**: `LOG_MUTEX` serialises `puts` calls; each log line is prefixed with `[HH:MM:SS][worker-N]` so per-thread activity is easy to follow.
- **Graceful shutdown**: `trap("INT")` / `trap("TERM")` set `$shutdown = true`; `interruptible_sleep` replaces bare `sleep` so threads wake within 1 second of the signal, finish any in-flight Ollama call, then exit cleanly. Main thread calls `threads.each(&:join)`.
- **Status page updated**: "Current activity" replaced by a "Workers (M/N active)" table showing every slot (idle or processing, with task ID, kind, model, step progress, elapsed time); history table gains a "Worker" column; JSON `/status.json` adds `concurrency` and `active_tasks` array.
- 197 Rails tests green; worker syntax verified (`ruby -c`).

### Added — Fragment caching for the news portal (no migrations)

- `ArticleStory` PORO now implements `cache_key` + `cache_key_with_version` (delegating to its `article`) so Rails' `cache` helper can fingerprint it alongside AR models.
- `NewsHelper#news_sidebar_cache_key` computes a stable, short fragment key for the sidebar from the sum of each sidebar story's `updated_at` epoch plus the total story count.
- Fragment caches added across all story-card partials and the article body:
  - `_post_item.html.erb` — `cache [story, story.article, news_lang, image_url, show_excerpt]`
  - `_overlay_card.html.erb` — `cache [story, story.article, news_lang, image_url, hero, tile]`
  - `_module_lead.html.erb` — `cache [story, story.article, news_lang, image_url, eager]`
  - `_sidebar.html.erb` — `cache news_sidebar_cache_key(...)` wrapping both the latest-news list and the category-count widget
  - `show.html.erb` — `cache [@translation, @article, news_lang, @image_url, @tags.join(",")]` wraps the article `<h1>`, image, body, tags, and source link
- `content_for` blocks and the breadcrumb nav on `show` remain outside the fragment and run every request (they populate layout `<head>` slots).
- Cache keys auto-bust on any AR `updated_at` change; no explicit TTL needed (the existing 10-min story-pool TTL serves as the outer backstop).
- Fragment caching is **off** by default in development — run `bin/rails dev:cache` to enable. Production already has `config.action_controller.perform_caching = true`.
- 197 tests green.

### Added — SEO, Google, bot, and LLM optimisations for the public news portal

**Google**
- `<meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large">` added site-wide.
- `<link rel="sitemap">` discovery tag added to every page head.
- `article:published_time`, `article:modified_time`, `article:section`, and `article:tag` Open Graph meta properties emitted on article show pages.
- `<meta name="author" content="BBC News">` added to show pages for E-E-A-T signals.
- JSON-LD on show pages upgraded to a `@graph` containing a `NewsArticle` (with `ImageObject`, `author`, `isAccessibleForFree`, `url`) and a `BreadcrumbList` (home → category → article).
- `WebSite` + `SearchAction` JSON-LD added to the homepage so Google can index a sitelinks search box.
- `ItemList` JSON-LD on the homepage lists the top 10 published stories.
- `Organization` JSON-LD (with logo) emitted on every page for Knowledge Graph identity.
- `og:image:alt` and `og:locale:alternate` added to Open Graph meta.
- `hreflang x-default` link added alongside the existing `fa`/`en` alternates.
- Hero and first-module-lead images upgraded to `loading="eager" fetchpriority="high"` for Core Web Vitals (LCP). All other images stay `loading="lazy"`.
- `<time datetime="ISO 8601">` elements wrap every story timestamp for structured date semantics (index, show, partials).
- `<link rel="preconnect" href="https://cdn.jsdelivr.net">` + `dns-prefetch` added to reduce CDN connection time.
- `<meta name="theme-color">` added for mobile browser UI.

**LLM / AI bots**
- `GET /llms.txt` (new route + `NewsController#llms`) serves an English plain-text site summary following the llmstxt.org convention — what the site is, section map, URL patterns, crawling guidance, JSON-LD inventory.
- `robots.txt` updated: explicit `Allow` blocks for `GPTBot`, `OAI-SearchBot`, `ChatGPT-User`, `PerplexityBot`, `anthropic-ai`, `Claude-Web`, `Applebot`, `Amazonbot`, `cohere-ai`, `CCBot`; all bots now see `Disallow: /admin` and `Disallow: /api`.

**197 tests green.**

### Changed — Friendly slugs for public news URLs (no numeric IDs)

- Public story URLs no longer contain a numeric article/translation ID.
  - Persian translations: `/news/عنوان-خبر` (was `/news/123-عنوان-خبر`)
  - English article stories: `/en/news/a-bbc-article-title` (was `/en/news/a456-bbc-article-title`)
- Migration `20260619000001` adds a unique `slug` string column to both `translations` and `articles`.
- `Translation` and `Article` models auto-generate a slug from the Persian/English title via `before_save :ensure_slug`; collisions are resolved with `-2`, `-3`, … suffixes.
- `Translation#seo_param` returns the stored slug (falls back to old `id-slug` format before migration runs so the site degrades gracefully).
- `ArticleStory#seo_param` returns `"a-<article-slug>"` (the `"a-"` prefix distinguishes untranslated article stories from translation slugs in `NewsController#show`).
- `NewsController#show` resolves all four URL formats: new slug, old `id-slug`, new `a-slug`, old `a<id>-slug`; old-format URLs 301-redirect to the canonical slug URL automatically.
- Admin portal-preview buttons updated to use `ArticleStory.new(article).seo_param`.
- New rake task `bin/rails bbc:backfill_slugs` populates the slug column for pre-existing rows (run once after `db:migrate`).
- 197 tests green.

### Fixed — Section header "more" link alignment in both portal editions

- `.block-title` converted from float-based layout to `display: flex; justify-content: space-between` so the "more ›" / "بیشتر ›" link always sits at the far end of the header row, opposite the category label.
- `float: left` was putting the link on the wrong side in LTR (English); flexbox handles RTL and LTR correctly without direction-specific overrides.
- Removed the mobile `float: none; display: block` override that was compensating for the float.

### Changed — English edition served under /en/ URL prefix

- All English-edition public URLs now use a `/en/` path prefix (`/en/news/…`, `/en/search`, `/en/category/…`, `/en` homepage) instead of `?lang=en` query params.
- Achieved by wrapping news routes in `scope "(:lang)", constraints: { lang: /en/ }` — `lang` is now an optional URL path segment, so `default_url_options { lang: "en" }` produces `/en/…` paths automatically.
- Added `GET /en` as the named `en_root` route for the English homepage.
- `lang_switch_url` helper updated to swap `/en` path prefix instead of the `?lang=` query param.
- Added `home_path`/`home_url` helpers for edition-aware homepage links.
- All `news_path`/`news_url`/`category_path` calls converted to keyword-argument form (`id:`, `category:`) since `(:lang)` is now the first URL segment.
- All tests and admin portal-preview links updated accordingly. 197 tests green.

### Fixed — Admin articles search routes by script (English vs Farsi)

- Farsi/Arabic-script queries (detected via Unicode range) search `translations.translated_title` via a LEFT JOIN + `.distinct`.
- Latin/English queries search `articles.title` and `articles.description` (BBC source fields) as before — no translation join.
- Previously English terms were also searching translated Farsi fields (or vice versa), mixing results across languages.

### Added — Jalali (Shamsi) date display in Persian news portal

- All calendar dates in the Persian edition now display in the Jalali calendar with Persian (Eastern Arabic) digits — e.g. "۲۸ خرداد ۱۴۰۵".
- `NewsHelper` gains three new methods: `gregorian_to_jalali` (pure-Ruby arithmetic conversion, no gem), `to_persian_digits` (converts ASCII digits to ۰–۹), and `jalali_date_string` (formats a Date/Time as a full Jalali string).
- `story_timestamp` now calls `jalali_date_string` for stories older than 7 days in the Persian edition; relative counts ("X دقیقه پیش" etc.) also use Persian digits for consistency.
- The topbar current-date display in `layouts/news.html.erb` uses `jalali_date_string` instead of `l(Date.current, format: :long)` in the Persian edition.
- English edition unchanged. 19 tests green.


### Added — Cancel button on pending tasks

- New `POST /admin/tasks/:id/cancel` route and `Admin::TasksController#cancel` action.
- Cancelling a pending task calls `fail!("Cancelled by admin")`, marking the task `failed`
  and its rewrite/translation target `error` (non-destructive — retryable from the Tasks page).
- Cancel button (red outline, confirm dialog) now appears next to every pending task row
  in the `/admin/tasks` index table.
- Cancel button also appears inline (next to the priority steppers) on `/admin/articles/:id`
  for any pending rewrite or translation task attached to that article.
- Only pending tasks can be cancelled; the action redirects back with an alert for any
  other status. 192 tests green.



### Added — Case-insensitive search + news portal search + keyword analytics

**Case-insensitive search across all admin listing pages**
- All `LIKE` queries in admin controllers now use `LOWER(col) LIKE LOWER(:q)`, making
  search case-insensitive on both SQLite (dev/test) and PostgreSQL (production).
  Affected controllers: `Admin::ArticlesController`, `Admin::RewritesController`,
  `Admin::TranslationsController`, and `Admin::TasksController`.

**Search for the public news portal**
- New `GET /search` route (`news#search`, named `news_search_path`).
- A search bar (input + submit button) appears in a slim bar between the masthead and
  main navigation on every public page. The search form uses `GET` so URLs are
  shareable and bookmarkable.
- FA edition searches `translations.translated_title` and `translations.translated_body`
  (case-insensitive); EN edition searches `articles.title` and `articles.description`.
  Results are capped to 30, de-duplicated to one story per article, and rendered with
  the existing `_post_item` partial including thumbnails.
- UI strings for the search feature added to `NewsHelper::UI_STRINGS` in both FA and EN.

**Search keyword analytics**
- New `search_queries` table (migration `20260618000002`): `keyword`, `edition`, `results_count`,
  `created_at`. Run `bin/rails db:migrate` on dev/prod to activate.
- `SearchQuery` model with `track!` class method (silently swallows errors if the table
  is absent, so the portal never breaks before migration).
- Every successful search call records the (normalised, lowercase) keyword, the edition,
  and the result count.
- Admin analytics dashboard gains a **Total searches** summary card and a **Top search keywords**
  table (top 20 by frequency, with quick FA/EN portal links per keyword, period-filtered
  like all other analytics). The card and table are hidden until the `search_queries`
  table exists.

### Added — Bump-priority shortcut for untranslated articles + IP geolocation fallback

**Admin articles index — bump priority when no FA translation exists**
- When a row has no published Persian translation, the 🇮🇷 portal link is replaced by
  an **⬆ FA** button (orange outline). Clicking it calls the new
  `POST /admin/articles/:id/bump_priority` action, which increments `priority + 1` on
  every pending Task tied to that article's rewrites and translations in one SQL UPDATE,
  then redirects back with a flash count. If no pending tasks exist, an alert is shown.

**ArticleView — IP geolocation fallback via Supabase edge function**
- `extract_country` now tries CDN headers first (Cloudflare / CloudFront / generic),
  then falls back to querying the Supabase `messagram` geolocation function with the
  client IP (`request.remote_ip`). Local/loopback IPs are skipped. Timeouts: 2 s open,
  3 s read. All errors are rescued and logged; the view never breaks on a slow or
  failing geo call.

### Added — Mobile-friendly portal, admin portal shortcuts, click-based priority, and analytics

**Mobile-friendly news portal (both FA and EN editions)**
- Viewport meta updated to `viewport-fit=cover` for notch phones.
- `col-lg-8/4` → `col-md-8/4` so the sidebar renders alongside content from tablet width.
- Mobile CSS overrides (`≤575px`): reduced hero card height (460→280px), smaller overlay
  titles, compact masthead/menu, tighter container padding, hidden topbar social icons.
- Sidebar gets a top separator when it stacks below the main column on mobile.

**Admin — mobile-friendly layout**
- Added a sticky dark top bar (hamburger `☰` + brand label) that appears only on
  `<768px` screens; the sidebar (`#adminSidebar`) toggles open/closed via a tiny JS
  function. Sidebar closes automatically when the user taps a nav link.

**Admin — portal preview shortcuts on articles**
- Articles index: each row now has 🇮🇷 (Persian portal, if a published translation
  exists) and 🌐 (English portal) icon buttons that open the story in a new tab.
  The controller preloads one translation per displayed article to avoid N+1.
- Articles show: "🇮🇷 Persian portal" and "🌐 English portal" buttons added to the
  top action bar. `@portal_translation` is set from the already-loaded translations
  list (no extra query).

**Click-based task priority bump**
- `NewsController#show` calls `bump_pending_task_priorities` after resolving the
  story: finds all pending Tasks whose target is a Rewrite or Translation of this
  article and runs a single `UPDATE … priority = priority + 1`. Readers clicking
  through to a story signal demand, moving its worker pipeline up the queue.

**Page-view analytics**
- New migration `20260618000001_create_article_views` (run `bin/rails db:migrate`
  to activate): `article_views` table with `article_id`, `translation_id`,
  `country_code` (2-char), `edition` (`fa`/`en`), `created_at`; indexed on
  `[article_id, created_at]`, `country_code`, and `created_at`.
- `ArticleView` model with `track!` class method called from `NewsController#show`.
  Country code is detected from Cloudflare (`CF-IPCountry`), CloudFront
  (`CloudFront-Viewer-Country`), or generic CDN (`X-Country-Code`) headers.
  Errors are logged and swallowed so a missing table never surfaces to readers.
- `Admin::AnalyticsController#show` (route `GET /admin/analytics`) aggregates
  total views, FA vs EN breakdown, top 15 countries, top 15 articles by views,
  and a daily sparkline — all scoped to a selectable period (7 / 30 / 90 days).
  Shows a migration-missing banner if the table doesn't exist yet.
- `ApplicationHelper` gains `country_flag(code)` (ISO→flag emoji via regional
  indicator characters) and `country_name(code)` (code→English name table).
- "📊 Analytics" added to the admin sidebar under Infrastructure.

### Fixed — Login page no longer shows admin menus
- `Admin::SessionsController` rendered its self-contained login view inside the
  `admin` layout, so the admin sidebar menus appeared to unauthenticated
  visitors on the login screen. Switched the controller to `layout false`.

### Added — Untranslated news visible in the English edition
- The English (`?lang=en`) edition of the public site now also surfaces recent,
  non-archived articles that have **no completed Persian translation yet**, so
  fresh BBC news shows up before the rewrite/translate worker pipeline finishes.
  The Persian edition is unchanged (translated stories only).
- New `ArticleStory` PORO wraps a raw `Article` in the Translation-story
  interface the news views use (`article`, `article_id`, `translated_title`,
  `translated_body`, `created_at`, `updated_at`, `seo_param`); its "translated"
  accessors fall back to the original English article fields.
- `NewsController#story_pool` merges these `ArticleStory` items into the pool for
  the English edition (capped, newest-first). `news#show` resolves an
  `"a<id>-slug"` param to an untranslated article story (digit-prefixed params
  remain translation stories).

### Added — Bilingual public news site + controller caching
- The public site is now bilingual. A `lang` query param selects the edition
  (`fa` default, `en`); `NewsController#set_news_lang` resolves it and
  `default_url_options` carries `?lang=en` across every generated link so the
  reader stays in the same edition. The English edition shows the **original**
  BBC article (article `title` + `description`); Persian shows the
  translation/refinement.
- New `NewsHelper` edition layer: `news_lang`/`english_edition?`,
  `news_ui(key)` (per-edition UI chrome strings), `story_title`/`story_body`
  (edition-aware content accessors), `category_name` + `CATEGORY_NAMES_EN`,
  localized `nav_categories`, English `story_timestamp`, and `lang_switch_url`
  (toggle to the other edition preserving the query string). Views/partials
  (`index`, `show`, `_overlay_card`, `_post_item`, `_module_lead`, `_sidebar`,
  `layouts/news`) now read through these helpers.
- Layout switches `<html lang/dir>` (RTL Vazirmatn ⇄ LTR Bootstrap), masthead,
  menu, footer and date formatting per edition, adds a top-bar language toggle,
  emits `og:locale` + reciprocal `hreflang` alternates; `show` JSON-LD uses the
  edition's `inLanguage`; `sitemap.xml` lists `fa`/`en` `xhtml:link` alternates.
- `NewsController#latest_translation_per_article` (the per-page story pool —
  loads every published translation + article/feed and sorts in Ruby) is now
  cached in `Rails.cache` (Solid Cache), keyed on a cheap content version
  (`story_pool_cache_key`: max translation/article `updated_at` + published
  count) with a 10-minute TTL backstop, so it recomputes only when the
  underlying data changes. The pool is language-agnostic (the edition only
  affects which fields views read). Added bilingual + caching tests; 188 green.
- Fixed a stale Subresource Integrity hash on the RTL Bootstrap stylesheet in
  `layouts/news` that was silently blocking it in the Persian (RTL) edition —
  so the Bootstrap grid/menu never loaded and categories rendered out of place.
  Corrected the `bootstrap.rtl.min.css` `integrity` to the actual published
  digest and gave the LTR `bootstrap.min.css` its verified SRI hash too.

### Added — Prioritize button on pending tasks on the article page
- `/admin/articles/:id` now shows the up/down priority stepper next to any
  rewrite/translation whose queue task is still pending. `ArticlesController#show`
  loads `@task_by_target` (the Task driving each rewrite/translation) and the
  rewrite/translation card headers render the shared `admin/tasks/_priority_controls`
  partial; `prioritize` already `redirect_back`s, so it returns to the article.
- Fixed two `chain_refine` refactor regressions that raised `ArgumentError`:
  `ArticlesController#multi_translate` passed the removed `chain_autopost:` kwarg
  (now `chain_refine: false`) and `Task#chain_refine!` called `enqueue_refine`
  with `ollama_server:` instead of `server:`. Added a translate→refine chain test
  and article-page prioritize-button tests. 184 tests green.
- (`chain_refine` column + `20260617000001_add_chain_refine_to_tasks` migration
  were already present and applied.)

### Changed — Public site brought closer to the tagDiv "Newspaper" demo
- Per-category color coding (the signature tagDiv look): new
  `NewsHelper::CATEGORY_COLORS` + `category_color`/`category_style` helpers feed
  an inline `--cat` custom property so each category's labels and section
  headers adopt their own accent (world=green, business=orange, tech=blue,
  science=purple, health=pink, uk=teal, top=red) instead of one global red.
- Homepage hero is now a mosaic "big grid": one large lead card plus up to four
  overlay tiles in a 2×2 grid (was one large + two stacked). Overlay cards gain
  a `tile` size and uppercase category labels.
- Homepage category sections are now full modules: a large lead post (big image,
  big title, excerpt) followed by a thumbnail list, with a colored block header
  and a "بیشتر ›" (more) link to the category page (was a flat list). New
  `news/_module_lead` partial; post-item thumbnails get a hover zoom.
- `news#show` article block adopts its category color too. No schema/route
  changes; all SEO preserved. 181 tests green.

### Changed — Public site redesigned as a Newspaper-style magazine
- Rebuilt the public news layout to mirror the tagDiv "Newspaper" demo: a top
  bar (date + social), centered masthead logo, a dark category menu bar (red
  active accent), a two-column body (content + sidebar), and a dark footer —
  all RTL/Persian with the Vazirmatn font and a red accent (#dd3333).
- Homepage: a hero block (one large featured story + two stacked, with category
  labels and titles overlaid on the images) followed by per-category section
  blocks (thumbnail-left post lists). Sidebar shows "latest news" + category
  counts. New category pages at `GET /category/:slug` (added `category` route)
  filter the main column to one feed category; the menu/sidebar link to them.
- Reusable partials `news/_overlay_card`, `_post_item`, `_sidebar`; new helper
  `nav_categories`/`story_time`. `news#show` restyled (breadcrumb, overlaid
  category label, full-width figure, tags) and now shares the sidebar. SEO
  (friendly URLs, meta, OG/Twitter, JSON-LD, sitemap) preserved. Added category
  + hero tests; updated index/show tests to the new markup. 181 tests green.

### Added — Admin House Keeping: abort all pending tasks
- New `/admin/housekeeping` page (sidebar item under Infrastructure) with an
  "Abort all pending tasks" action. `Task.abort_pending!` marks every pending
  task `failed` ("Aborted by admin") and stops its rewrite/translate/refine
  target (status → error); it's non-destructive (re-queue from the Tasks page)
  and leaves claimed/completed tasks and `feature`/`tag` anchor targets
  untouched. Added `Admin::HousekeepingControllerTest`.

### Added — SEO: friendly URLs, meta tags, structured data, sitemap
- Friendly public URLs: `Translation#seo_param` builds `"<id>-<persian-slug>"`
  (id prefix so `params[:id].to_i` recovers the PK on PostgreSQL — no slug
  column). `to_param` is deliberately NOT overridden, so admin routes keep the
  numeric id. `NewsHelper#news_story_path/url` build the public links.
- `news#show` 301-redirects any non-canonical slug to the canonical URL to avoid
  duplicate-content indexing.
- News layout `<head>` now emits per-page `<title>`, meta description, canonical
  link, Open Graph + Twitter Card tags (with the article image when present);
  `news#show` adds `NewsArticle` JSON-LD structured data.
- Added `GET /sitemap.xml` (homepage + every published story) and a dynamic
  `GET /robots.txt` (so the `Sitemap:` directive uses the real request host;
  the static placeholder `public/robots.txt` was removed). Added SEO tests.

### Added — AI-generated tags for news articles
- New `TagGenerator` service + `tag` Task kind: `bbc:tag` enqueues one tag task
  per untagged translated article; the worker runs the LLM request (Persian
  title+body → up to 6 short Persian topic tags) and the parsed tags are cached
  per article in Rails.cache (`article_tags/<id>`, 30-day TTL — no schema
  change). `news#show` renders the tags as chips. `tag` tasks anchor on the
  translation as a read-only target (never change its status).
- Added `TagGeneratorTest` + tag-kind `TaskTest` cases + a show-page tags test.

### Added — AI-selected featured stories + homepage thumbnails
- Homepage thumbnails: `news#index` resolves each story's image via
  `ArticleImageFetcher.call_many` (cache-first, cache misses fetched with
  bounded concurrency) and renders them on the lead + story cards.
- `FeaturedSelector` chooses which stories are featured: a heuristic (high-impact
  categories, newest first) is used immediately and as a fallback, while
  `bbc:feature` enqueues a `feature` Task whose LLM request asks the model to
  pick the most newsworthy article IDs; the worker's choice is cached
  (`featured_article_ids`, 3-day TTL) and takes precedence. The homepage shows a
  ★ ویژه lead + featured cards above the rest.
- `feature` Task kind is targetless in spirit (anchors on a candidate only to
  satisfy the NOT NULL target; never mutates it). Worker needs no changes — it
  is kind-agnostic. Added `FeaturedSelectorTest` + feature-kind `TaskTest` cases.

### Added — Article main image on the public news page
- `news#show` now displays the article's main image, read from the `og:image`
  meta tag of its original BBC source page via the new `ArticleImageFetcher`
  service. The lookup is SSRF-guarded (BBC host allow-list) and cached in
  Rails.cache / Solid Cache for a week (misses cached too), so each source page
  is fetched at most once — no schema change, the image is resolved on demand.
- Added `NewsControllerTest` (index latest-per-article + archived exclusion;
  show with/without an image, source page stubbed via WebMock). 154 tests green.

### Added — Public BBC-Persian-style news site
- New unauthenticated public front end at the site root showing the latest
  translated/refined Persian news, styled after BBC Persian (RTL, Vazirmatn
  font, dark header with BBC mark, lead story + two-column story grid).
- `NewsController#index` lists one story per article — the most recently created
  completed, non-archived translation that has Persian text — so a finished
  refinement (a `Translation` with `prompt_name: "refine"`) supersedes the
  translation it improved. `#show` renders the full translated article with a
  link back to the original BBC source.
- Routes: `root` now points to `news#index` (was a redirect to `/admin`);
  added `resources :news, only: %i[index show]`. Admin remains at `/admin`.
- Added `app/views/layouts/news.html.erb` (public layout), `news/index` +
  `news/show` views, and `NewsHelper` (Persian category names + relative
  "x ago" timestamps).

### Added — Worker interface design document
- Added `worker_design.md`: a self-contained specification/prompt describing the
  full worker API contract (endpoints, task payload schema, requests/responses
  format, authentication, model filtering, stale reclaim, lifecycle, chaining,
  and an implementation checklist) so any other Rails app can implement the same
  interface and be served by the same `worker/worker.rb` client.

### Added — Worker status page
- `worker/worker.rb` now serves a self-contained status page over a stdlib-only
  HTTP server (`TCPServer`/`socket`, no web framework, no new gems — only added
  `require "socket"`, `"cgi"`, and `"time"`).
- New thread-safe `WorkerState` class tracks the current phase
  (`starting`/`idle`/`processing`/`error`), the in-flight task with per-request
  progress (`request 2/3 — <key>`), completed/failed totals, last poll time,
  and a rolling 50-entry history of finished tasks (kind, model, status,
  duration, finish time, error).
- Ollama discovery refactored into `fetch_ollama_models` which reports
  reachability separately from the model list; the status page shows a
  reachable/unreachable badge, last-checked time, and the available models.
- Endpoints: `GET /` (auto-refreshing HTML dashboard, light/dark aware) and
  `GET /status.json` (machine-readable snapshot); unknown paths return 404.
- New config: `STATUS_PORT` (default `4567`) and `STATUS_BIND` (default
  `0.0.0.0`). If the port is busy the worker logs a warning and continues
  without the status page. `$stdout.sync` enabled for live log streaming.
- `worker/README.md` documents the status page, JSON endpoint, and new env vars.

### Fixed — Action Cable tests and stream name clarification
- Added `test/channels/application_cable/connection_test.rb` with 3 cases:
  anonymous connection rejected, `admin_logged_in: false` rejected, valid session accepted.
- Added 5 broadcast tests to `task_test.rb` (include `ActionCable::TestHelper`) covering
  `mark_claimed!`, `complete!` (rewrite & translate), `fail!`, and isolation (no bleed to
  other articles).
- Tests revealed that `broadcast_refresh_to` routes through Turbo's `stream_name_from`,
  which returns the raw string `"article_<id>_tasks"` — not the `"turbo:streams:…"` prefix
  that `broadcasting_for` returns. `assert_broadcasts` must use the raw name directly.
- 147 tests green.

### Fixed — TranslationRefiner uses separate prompts for title and body
- Replaced the single shared `SYSTEM_PROMPT` with `TITLE_PROMPT` and `BODY_PROMPT`.
- `TITLE_PROMPT` instructs the LLM to output only a short refined headline with no body.
- `BODY_PROMPT` instructs the LLM to output only the refined body text with no title.
- This prevents the LLM from bleeding content between the two fields (e.g. generating
  a full article when given only a headline, or prepending a title to the refined body).
- `debug_curl_title` and `debug_curl_body` updated to use the matching prompt.
- 139 tests green.

### Added — Action Cable live updates on article show page
- When a worker claims, completes, or fails a task belonging to an article,
  the article show page now automatically refreshes via Action Cable + Turbo
  Streams — no manual page reload needed to see updated rewrite/translation
  statuses and content.
- Enabled `action_cable/engine` in `application.rb` (was commented out).
- Added `config/cable.yml` with the `async` adapter for all environments.
- Created `app/channels/application_cable/connection.rb` — rejects anonymous
  connections; allows connections with a valid admin session
  (`session[:admin_logged_in]`).
- Created `app/channels/application_cable/channel.rb` — base channel stub.
- Mounted `ActionCable.server` at `/cable` in `config/routes.rb`.
- `Task#mark_claimed!`, `Task#complete!`, and `Task#fail!` each call a private
  `broadcast_article_refresh` helper that invokes
  `Turbo::StreamsChannel.broadcast_refresh_to("article_<id>_tasks")`.
- Article show view adds `<%= turbo_stream_from "article_#{@article.id}_tasks" %>`
  to subscribe the browser to that stream; a `<turbo-stream action="refresh">`
  broadcast triggers a Turbo page refresh automatically.

### Added — Translate dropdown on each rewrite card
- Each completed rewrite card on the article show page now has a card footer with
  a translate form, so an operator can queue a translation for a specific rewrite
  without using the top-level multi-translate panel.
  - One translate target configured → single "with `<model>`" button.
  - Multiple translate targets → `<select>` dropdown + "Translate" button.
  - Posts to `multi_translate` with the rewrite's id pre-filled as `rewrite_id`;
    the controller uses it to translate from that exact rewrite.
- `translate_targets` computation moved before the rewrites loop so it is available
  in both the rewrite card footers and the translate panel (no duplication).
- 139 tests green.

### Changed — Simplified rewrite/translate buttons when only one target exists
- When exactly one server/model combination is configured for rewrites (or
  translations), the article show page now renders a single direct button instead
  of the collapsible multi-target panel with checkboxes.
  - Single rewrite target → "Rewrite with `<model>`" button, posts directly to
    `multi_rewrite` with the target pre-filled.
  - Single translate target → "Translate with `<model>`" button, posts directly to
    `multi_translate`; rewrite source auto-selected (latest completed rewrite, or
    original if none).
  - Multiple targets → unchanged collapsible panel with checkboxes.
- 139 tests green.

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
