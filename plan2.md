# bbcfarsi — Comprehensive Code Review & Strategic Improvement Plan (plan2.md)

> **Scope:** Full review of the Rails 8 app (`app/`, `config/`, `db/`, `lib/`), the standalone
> Ruby worker (`worker/worker.rb`), and repo hygiene. **No code was changed** — this document is
> analysis and planning only.
>
> **Evidence base:** every file in `app/` reviewed; `db/schema.rb`, routes, initializers,
> deploy/env config, and the 702-line worker read in full. Test suite executed:
> **394 runs, 1 192 assertions, 0 failures**. Brakeman executed: **1 medium warning**
> (mass assignment of `role`/`active` in `Admin::UsersController` — admin-only, see M-9).
>
> Date: 2026-07-11
>
> **Status update (2026-07-16):** Phase 0 (§10) AND Phase 1 (§10) have both been
> implemented — see the "Phase 0 implementation status" / "Phase 1 implementation
> status" notes under §10 and the CHANGELOG entries "Fixed — Phase 0 security
> hardening..." and "Fixed — Phase 1 pipeline reliability...". Phases 2–4 are
> still just this planning document; no code for them has been written.

---

## Table of Contents

1. [System overview](#1-system-overview)
2. [Critical issues (must fix)](#2-critical-issues)
3. [High-priority issues](#3-high-priority-issues)
4. [Medium-priority issues](#4-medium-priority-issues)
5. [Low priority / hygiene](#5-low-priority--hygiene)
6. [Code & logic improvements (refactors)](#6-code--logic-improvements)
7. [Architecture & design assessment](#7-architecture--design-assessment)
8. [Proposed new features](#8-proposed-new-features)
9. [Metrics & validation](#9-metrics--validation)
10. [Phased roadmap](#10-phased-roadmap)

---

## 1. System overview

The app is an automated bilingual news pipeline:

```
RSS (BBC/NYT) ─▶ FeedIngestor ─▶ Article ─▶ Task(rewrite) ─▶ Task(translate) ─▶ Task(refine)
                                                 │                                   │
                                    llmarkt grid (webhooks, primary)                 ▼
                                    Ollama worker (pull API, fallback)     Telegram admin bot,
                                                                           autopost, public portal
```

Strengths worth preserving:

- **Clean task-queue decoupling** — the Rails app never calls an LLM; `Task` rows +
  a bearer-token API + webhook callbacks keep GPU concerns out of the web tier.
- **Prompt versioning** (`Prompt`/`PromptVersion`/`PromptVersionUsage`) with full
  provenance from output back to the exact prompt version. This is genuinely better
  than most production LLM apps.
- **Audit trail** (PaperTrail + activity log), roles, last-active-admin safeguard.
- **Credentials-first config modules** (`Llmarkt`, `MailerConfig`, `TelegramAdminBot`,
  `AdminBootstrap`) with a consistent pattern.
- **Disciplined tests** (394 green) that grew with every feature.

The dominant weaknesses are: (a) session/auth hardening gaps, (b) a duplicate-execution
race between the llmarkt path and the stale-task reclaimer, (c) synchronous third-party
I/O on public request paths, and (d) unbounded data/memory growth in the story pool,
analytics, and versions tables.

---

## 2. Critical issues

**(must-fix for security/stability)**

### C-1. Deactivated users keep working sessions — ✅ DONE (2026-07-16)

[application_controller.rb:14-16](app/controllers/application_controller.rb#L14-L16)

```ruby
def current_user
  @current_user ||= User.find_by(id: session[:user_id])   # no `active` check
end
```

`User.authenticate` checks `active` **only at login** ([user.rb:31-34](app/models/user.rb#L31-L34)).
Disabling a user at `/admin/users` (the intended kill switch, e.g. for a departed editor)
does **not** end their existing session — they keep full access until the cookie expires.
`Admin::SessionsController#logged_in?` has the same gap.

**Fix:** `User.active.find_by(id: session[:user_id])`. One-line change; add a request test
"disabled user with a live session is redirected to login".

### C-2. No `reset_session` on login (session fixation) — ✅ DONE (2026-07-16)

[sessions_controller.rb:14-16](app/controllers/admin/sessions_controller.rb#L14-L16) sets
`session[:user_id]` without calling `reset_session` first, so a session ID planted before
authentication survives it (classic fixation; also flagged by Rails security guide).
Also call `reset_session` on logout instead of only `session.delete(:user_id)`.

### C-3. No rate limiting on authentication endpoints — ✅ PARTIALLY DONE (2026-07-16)

> Login and password-reset rate limits are in; the search-tracking write
> (`GET /search` + `SearchQuery.track!`) is **not** rate-limited yet — that part
> is tracked under H-7 in Phase 2, not Phase 0.

- `POST /admin/login` — unlimited password guessing against known usernames.
- `POST /admin/password_resets` — unlimited outbound reset emails (mail-bomb + Resend quota burn).
- `GET /search` + `SearchQuery.track!` — every request writes a row (see H-7).

Rails 8 ships `rate_limit` in controllers. Suggested:

```ruby
# Admin::SessionsController
rate_limit to: 10, within: 3.minutes, only: :create
# Admin::PasswordResetsController
rate_limit to: 5, within: 15.minutes, only: :create
```

### C-4. Duplicate task execution: stale-reclaim vs. llmarkt in-flight jobs — ✅ DONE (2026-07-16)

Three facts that conflict:

| Fact | Where |
|---|---|
| Tasks submitted to llmarkt are marked `claimed` and given `timeout_seconds: 20.minutes` | [llmarkt_submitter.rb:56](app/services/llmarkt_submitter.rb#L56) |
| A `claimed` task idle **> 15 minutes** is auto-returned to `pending` on *every worker poll* | [task.rb:26](app/models/task.rb#L26), [task.rb:116-138](app/models/task.rb#L116-L138) |
| `requeue!` clears responses but **not** `external_job_id`, and never cancels the remote job | [task.rb:239-243](app/models/task.rb#L239-L243) |

Consequence: any llmarkt job that legitimately runs 15–20 minutes (exactly what the
20-minute timeout allows) gets reclaimed while still running. The Ollama worker then claims
it, and *both* backends execute it; the late webhook can then interleave with the worker's
processing (`handle_callback` re-records responses and re-chains — enqueuing **duplicate
translate/refine tasks** and duplicate Telegram notifications). `mark_claimed!` on a worker
claim doesn't clear `external_job_id` either, so priority/retry mirroring can target a
job that no longer corresponds to the task.

**Fix (in order of importance):**
1. `STALE_AFTER` must exceed the llmarkt `timeout_seconds` (e.g. 25–30 min), or better:
   store a per-task `stale_at` deadline derived from the backend it was handed to.
2. `requeue!` should clear `external_job_id` and (best-effort) call a llmarkt cancel
   endpoint if/when available.
3. `LlmarktSubmitter.handle_callback` should run inside `task.with_lock` and ignore
   callbacks whose `external_job_id` no longer matches the payload's `job_id`
   (the payload already carries it).
4. Add a `Task` status guard in `complete!`/`fail!` (`return if completed?`) so a second
   completion is a no-op instead of re-running chains.

> **Implementation note (2026-07-16):** items 1, 2, 3, and 4 all shipped.
> `Task::LLMARKT_JOB_TIMEOUT` (20 min) is now the single source of truth
> `LlmarktSubmitter#submit_request` reads for the llmarkt `timeout_seconds`,
> and `STALE_AFTER` is derived from it (+10 min buffer) instead of a flat,
> shorter 15 minutes. `requeue!` clears `external_job_id`. `handle_callback`
> gained a sibling `handle_failure` (for the `"failed"` webhook path, which
> previously called `task.fail!` directly with no staleness check); both run
> inside `task.with_lock` and ignore a callback/failure whose `job_id`
> doesn't match `task.external_job_id` via a new `stale_job?` guard.
> `Api::LlmCallbacksController` now forwards `params[:job_id]` into both.
> **Not done:** best-effort llmarkt job cancellation on reclaim (no such
> endpoint exists in the vendor API today per `LlmarktClient`); a live chaos
> test (kill worker mid-task, let llmarkt time out, replay duplicate
> webhooks) — verified instead via unit tests plus a scripted
> `bin/rails runner` smoke check of `complete!` idempotency and `requeue!`
> clearing `external_job_id`.

### C-5. CSRF protection weakened on a state-changing admin controller — ✅ DONE (2026-07-16)

[translations_controller.rb:3](app/controllers/admin/translations_controller.rb#L3)

```ruby
protect_from_forgery with: :null_session
```

This controller mutates content, posts to Telegram, and flags manual edits. `null_session`
means a forged request without a token is *not rejected* — it proceeds with a nulled
session (mitigated only because `require_login` then fails). It's the only controller with
this override — almost certainly a leftover from debugging. Remove it; if some endpoint
needed token-less access it should be under `Api::` with explicit auth.

> **Correction (2026-07-16):** this was *not* the only controller with the override —
> `Admin::RewritesController` had an identical `protect_from_forgery with: :null_session`
> line that this review missed. Both were removed together; both now inherit the app's
> default `:exception` forgery protection.

### C-6. Host authorization disabled in production — ✅ DONE (2026-07-16)

[production.rb:59-66](config/environments/production.rb#L59-L66) — `config.hosts` is commented
out. Any request with an arbitrary `Host:` header is served; URLs built from
`request.base_url` (`robots`, `sitemap_url`, `llms`, canonical/OG tags on the public site)
will echo an attacker-controlled host — cache-poisoning and SEO-poisoning vector, and the
exact class of issue `hosts` exists to stop. Set the real domain(s) and exclude `/up`.

> **Implementation note (2026-07-16):** no real production domain was configured anywhere
> in the repo yet (`config/deploy.yml`'s `proxy.host` is still the Kamal template placeholder
> `app.example.com`). Rather than guess/hardcode a domain, `config.hosts` is now derived at
> boot from the existing `app_base_url` credential / `APP_BASE_URL` env var — the same value
> `Llmarkt.app_base_url` and the mailer's `default_url_options` already use for this app's
> public URL. Whoever sets the real `APP_BASE_URL` for deploy automatically gets the correct
> `config.hosts` entry; no separate variable to keep in sync.

---

## 3. High-priority issues

### H-1. Blocking third-party geolocation call in the public request path

[article_view.rb:69-84](app/models/article_view.rb#L69-L84) — every story view from a new IP
does a **synchronous `Net::HTTP` call** (2 s open + 3 s read timeout) to the geo service
inside the reader's request. Under a crawl or traffic spike from many IPs this pins Puma
threads for up to 5 s each. Additional problems in the same file:

- `GEO_URL = Rails.application.credentials.dig(:geo_url)` is a **boot-time constant**;
  if unset, `URI(GEO_URL+ip)` raises `NoMethodError` on every view (swallowed, geo dead,
  one log line per view).
- `CF_COUNTRY_HEADER` / `CF_FRONT_HEADER` / `GENERIC_COUNTRY_HDR` are **defined but never
  used** — the cheap CDN-header path documented in the plan was silently replaced by the
  HTTP lookup.

**Fix:** prefer CDN headers when present (free, instant); otherwise enqueue the lookup
(see the "in-app background execution" decision in §7.3) and write the row with
country=nil, backfilling asynchronously. Never do third-party HTTP in the render path.

### H-2. Full feed ingest runs synchronously inside admin HTTP requests

[articles_controller.rb:15](app/controllers/admin/articles_controller.rb#L15)
(`FeedIngestor.run if params[:trigger_fetch]`) — after the NYT catalog expansion this is
**~80 sequential RSS fetches** in one request; each feed has **no HTTP timeout** (H-3), so a
single slow feed can hang the request past any proxy timeout. The per-feed
`POST /admin/feeds/:id/fetch` path is fine; the "Fetch now" button is not.

**Fix:** move `FeedIngestor.run` to background execution (§7.3) and flash "fetch started";
or at minimum fetch concurrently with a hard per-feed timeout and an overall budget.

### H-3. No timeouts on RSS fetching — ✅ PARTIALLY DONE (2026-07-16)

[feed_fetcher.rb:47](app/services/feed_fetcher.rb#L47) — `HTTParty.get(feed.url,
follow_redirects: false)` has **no `timeout:`** (HTTParty's default is *no timeout*).
Combined with H-2 this is the biggest availability risk in the admin. Add
`timeout: 10` (or `open_timeout`/`read_timeout`) and a `Down`-style max-size guard.

> **Implementation note (2026-07-16):** `timeout: 10` added. The `Down`-style
> max-size guard (capping response body size, not just time) is **not**
> done — H-2 (moving the "Fetch now" admin trigger off the request thread
> entirely) is also still open; both remain Phase 2 work.

### H-4. `ArticleImageFetcher`: request-path fan-out, DB-pool pressure, SSRF-via-redirect

[article_image_fetcher.rb](app/services/article_image_fetcher.rb)

- **Request-path fan-out:** homepage/category/search all call `call_many` for *every
  displayed story*; on cache expiry (1-week TTL, cold cache after deploy/cache clear) a
  single request fetches dozens of BBC/NYT pages before rendering. `MAX_CONCURRENCY = 6`
  bounds parallelism, not total work.
- **DB pool exhaustion:** each of the 6 threads uses `Rails.cache` (Solid Cache → **database
  connections**). With the default pool of 5 (`RAILS_MAX_THREADS`), 6 cache-writing threads
  inside an already-checked-out request thread can exhaust the pool under concurrency →
  `ActiveRecord::ConnectionTimeoutError` on unrelated requests.
- **SSRF-via-redirect:** the allow-list checks the *initial* host only; `URI.open` follows
  redirects to *any* host (including internal addresses). BBC/NYT are trusted, but a
  compromised short-link in a feed defeats the guard. Also `URI::HTTP` accepts plain http.
- Cached misses (`""`) mean a transient network error blanks an article's image for a week.

**Fix:** resolve images **at ingest/complete time, not render time** — persist
`articles.image_url` (one nullable string column) filled by background work; keep the
fetcher but with `open_uri` `redirect: false` (or manual redirect loop re-validating each
hop against the allow-list), https-only, and distinguish "no og:image" (cache long) from
"fetch failed" (cache minutes).

### H-5. `Task#complete!` is not atomic and failure handling can corrupt state — ✅ DONE (2026-07-16)

[task.rb:178-207](app/models/task.rb#L178-L207) performs 3–5 sequential writes (target
update, `activate!`, article status, chain-enqueue, own status) with **no transaction**.
[api/tasks_controller.rb:21-28](app/controllers/api/tasks_controller.rb#L21-L28) then does:

```ruby
task.complete!(responses_param)
rescue StandardError => e
  task&.fail!(e.message)      # ← flips target to "error" even if it was just updated to "completed"
```

If the failure happened *after* the target was completed (e.g. chain enqueue raised), the
rescue marks a good result as `error` and the article as `error`. Wrap the state writes in
a transaction, set the task `completed` *before* running side-effect chains, and rescue
chain errors separately (they already are for autopost/notify — extend to `chain_translate!`
/ `chain_refine!` which currently `create!` unrescued).

> **Implementation note (2026-07-16):** `complete!` now wraps the
> target/article/task status writes in one `ActiveRecord::Base.transaction`
> and only runs the chain (`chain_translate!`/`chain_refine!`/
> `chain_autopost!`/`notify_admin_bot!`) after that commits; `chain_translate!`
> and `chain_refine!` are now individually rescued like `chain_autopost!`
> already was. Combined with the `return if completed?` idempotency guard
> from C-4, `Api::TasksController#complete`'s rescue path is now safe as-is
> (needed no controller change): any exception before the transaction
> commits rolls back cleanly, so there's nothing for `task.fail!` to
> corrupt.

### H-6. Story pool and sitemap load the entire published corpus into memory

[news_controller.rb:300-310](app/controllers/news_controller.rb#L300-L310) —
`latest_translation_per_article` loads **every** completed translation (with articles and
feeds), groups in Ruby, sorts in Ruby. The 10-minute cache hides it today, but: each cache
miss gets slower forever; the cached blob itself (all rows marshalled into Solid Cache → DB)
grows without bound; `sitemap` uses the same query uncached-per-request pattern. The
`story_pool_cache_key` also runs 3 aggregate queries on *every* page view just to build the key.

**Fix:** replace Ruby grouping with SQL — on PostgreSQL `DISTINCT ON (article_id) … ORDER BY
article_id, created_at DESC` (SQLite: window function `ROW_NUMBER() OVER (PARTITION BY …)`,
supported since 3.25) — and cap the homepage pool (e.g. newest 120 stories). Paginate the
sitemap once it passes a few thousand URLs (sitemap-index).

### H-7. Public endpoints do unauthenticated database writes (bot amplification)

Every anonymous request can write rows / mutate state:

| Endpoint | Write | Risk |
|---|---|---|
| `GET /news/:id` | `ArticleView.create!` + geolocation row | table grows per crawler hit |
| `GET /news/:id` | `bump_pending_task_priorities` (+1 every view) [news_controller.rb:314-320](app/controllers/news_controller.rb#L314-L320) | bots inflate priorities unboundedly, starving other tasks; also a write per read |
| `GET /search?q=…` | `SearchQuery.create!` (unlimited, attacker-chosen strings) | junk analytics + table growth |

**Fix:** rate-limit + bot-filter (skip tracking when UA matches known crawlers), clamp the
priority bump (e.g. only once per task, or cap priority), cap `keyword` length, and add
retention pruning (M-8). Note the priority bump also bypasses the llmarkt mirror that
`reprioritize!` maintains — priorities silently diverge between systems.

### H-8. Telegram Markdown breakage on real-world titles — ✅ DONE (2026-07-16)

[telegram_poster.rb:16-23](app/services/telegram_poster.rb#L16-L23) and
[telegram_admin_notifier.rb:149-165](app/services/telegram_admin_notifier.rb#L149-L165) send
LLM-generated text with `parse_mode: "Markdown"` and **no escaping**. Any title/body
containing an unbalanced `*`, `_`, `[`, or backtick makes the Telegram API reject the whole
message → autopost/notification fails (and with H-5, can mark things failed). Persian news
text does contain these. **Fix:** escape entities (or switch to HTML parse mode with
`CGI.escapeHTML`, which is much easier to get right).

> **Implementation note (2026-07-16):** switched to `parse_mode: "HTML"` with
> `CGI.escapeHTML` on every interpolated value in both files, as suggested.

### H-9. `ArticleTranslator.process` doesn't strip `<think>` blocks — ✅ DONE (2026-07-16)

[article_translator.rb:31-36](app/services/article_translator.rb#L31-L36) — the rewriter and
refiner both strip `<think>…</think>` reasoning; the translator does **not**. Configure a
reasoning model (qwen3 family, already used for rewrites) as a translate model and its
chain-of-thought is published verbatim on the portal and Telegram. One-line fix; share one
`StripsThink` helper across the three services (they have three copies of the same regex).

> **Implementation note (2026-07-16):** new `LlmText.clean` (`app/services/llm_text.rb`)
> replaces all three copies of the regex (`ArticleRewriter`, `TranslationRefiner`,
> and the previously-missing call in `ArticleTranslator.process`).

### H-10. Missing database indexes for the hottest queries

From `db/schema.rb` vs. actual query shapes:

| Table | Missing index | Used by |
|---|---|---|
| `translations` | `(status, archived)` (or partial `WHERE status='completed' AND archived=false`) | `published_translations` — every public page |
| `translations` | `needs_manual_edit` (partial `WHERE needs_manual_edit`) | sidebar badge count on **every admin page** ([application_helper.rb:26-28](app/helpers/application_helper.rb#L26-L28)) |
| `translations` | `(article_id, created_at)` | latest-per-article, portal preview |
| `articles` | `published_at`, `(archived, published_at)` | story pool, EN-edition extras, search |
| `articles` | `status` | admin filters/counts |
| `versions` | `whodunnit`, `created_at` | activity-log filtering |
| `article_views` | `(created_at, edition)`, `translation_id` | analytics windows |
| `tasks` | `(status, kind)` | admin cross-filter counts |

Cheap win; measure before/after with `EXPLAIN ANALYZE` on production-sized data.

### H-11. Action Cable `async` adapter in production — ✅ DONE (2026-07-16)

[cable.yml](config/cable.yml) — `production: adapter: async` only delivers broadcasts to
subscribers **in the same process**. Works today (single Puma container) but silently breaks
with >1 web process/container, and broadcasts fired from rake tasks (`bbc:*`) or a console
never reach browsers. Rails explicitly warns against `async` in production. **Fix:** Solid
Cable (DB-backed, fits the existing Solid-* stack, no Redis needed).

> **Implementation note (2026-07-16):** added the `solid_cable` gem;
> `config/cable.yml` production now uses `adapter: solid_cable`, folded into
> the primary database (no `connects_to`/separate `cable` db — no `database:`
> key, same as Solid Cache) via a new `solid_cable_messages` table/migration.
> **Not run:** `bin/rails db:migrate` on dev/prod (per project rules) — the
> table needs to exist before Solid Cable can actually write to it.

### H-12. Task claiming: no `SKIP LOCKED`, stale-reclaim inside the claim transaction — ✅ DONE (2026-07-16)

[task.rb:116-130](app/models/task.rb#L116-L130) — `pending.by_priority.lock.first` on
PostgreSQL serializes all concurrent workers on the same head-of-queue row (plain
`FOR UPDATE`); with `WORKER_CONCURRENCY=4` pollers every 5 s this is contention for nothing.
`reclaim_stale!` (which loads and updates *N* stale tasks plus their targets) also runs
*inside* that transaction, lengthening the lock hold.
**Fix:** `lock("FOR UPDATE SKIP LOCKED")` on PG (SQLite ignores locking anyway), move
`reclaim_stale!` out of the transaction (it's idempotent), and keep it on the cron path.

> **Implementation note (2026-07-16):** both changes shipped exactly as
> suggested — `Task.claim_next!` now locks with `.lock("FOR UPDATE SKIP LOCKED")`
> and calls `reclaim_stale!` before opening the claim transaction.

### H-13. `allow_browser versions: :modern` blocks readers on the public portal — ✅ DONE (2026-07-16)

[application_controller.rb:2](app/controllers/application_controller.rb#L2) applies to the
**news site**, not just the admin. Persian-audience traffic skews toward older Android
WebView/Chrome builds; those readers get a bare 406 page. Move `allow_browser` to
`Admin::BaseController` (or drop it) and let the public site degrade gracefully.

---

## 4. Medium-priority issues

### M-1. Slug generation: comment/code mismatch, ugly collisions, race

[article.rb:68-87](app/models/article.rb#L68-L87), [translation.rb:67-77](app/models/translation.rb#L67-L77)
— comments promise `-2`, `-3` suffixes; the code appends `rand(10**16)` → a colliding slug
becomes `عنوان-8437263948572615`. The check-then-save pattern also races (two concurrent
saves → `RecordNotUnique` bubbles to the user). Use sequential suffixes with a bounded loop
and rescue/retry on the unique-index violation.

### M-2. `Article.status` is a single-value state machine over a parallel pipeline

`pending → rewriting → rewritten → translating → translated → posted / error` — but an
article can have *several* rewrites/translations in flight (that's the whole
multi-server-comparison feature). One failing translation marks the entire article `error`
([task.rb:209-218](app/models/task.rb#L209-L218)) even when another translation succeeded;
`posted` strikes the title through everywhere even if only one channel got it. Derive
display state from children (or keep per-target status only), rather than mutating a global
scalar from every task callback.

### M-3. AI tags and featured-story picks live only in the cache

[tag_generator.rb:38-52](app/services/tag_generator.rb#L38-L52),
[featured_selector.rb:46-54](app/services/featured_selector.rb#L46-L54) — paid-for LLM output
is stored in Solid Cache with TTLs (30 d / 3 h). Cache clear (deploy hygiene, `db:prepare`
on a fresh DB, manual flush) silently deletes all tags until someone re-runs `bbc:tag`.
Persist to real columns/tables (`article_tags`, `featured_selections`) and treat cache as
cache. This also unblocks tag landing pages (feature F-3).

### M-4. Three autopost paths with diverging semantics — ✅ PARTIALLY DONE (2026-07-16)

1. `chain_autopost!` → `Autoposter.post_translation` — respects `TelegramChannel.autopost`.
2. `bbc:autopost` sweep — respects `autopost`.
3. Admin-bot `auto_publish_to_sole_channel!` ([telegram_admin_notifier.rb:209-218](app/services/telegram_admin_notifier.rb#L209-L218))
   — fires on **`enabled`** channels, *ignoring* the `autopost` flag.

A channel configured "enabled but not autopost" (manual-only) is still auto-posted the
moment a refine completes, as long as it's the only enabled channel — contradicting the flag's
meaning. Also `TelegramPost` uniqueness is only enforced by lookup, not by a DB unique index
on `(translation_id, telegram_channel_id)` — the sweep + chain + bot can race into duplicates.
Consolidate into one `Publisher` service + unique index.

> **Implementation note (2026-07-16):** the unique-index + `Publisher`
> consolidation shipped for paths 1 and 2 (`Autoposter#post_translation`/
> `#run_all` and `Admin::TranslationsController#post_to_channel` and
> `TelegramAdminNotifier#post_to_channel` — the admin-UI/admin-bot one-tap
> post button — all now go through `Publisher.post_to_channel`). Path 3 as
> described here (`auto_publish_to_sole_channel!` firing without a tap,
> ignoring `autopost`) turned out to **no longer exist** — a prior session
> ("Telegram admin bot: skip channel picker... keep one-tap confirm") had
> already replaced it with a one-tap confirm button before this review ran,
> so the "manual-only channel gets silently auto-posted" contradiction this
> item describes doesn't currently apply. Left as partially-done since the
> semantic-divergence audit (do all paths still agree on what `autopost`
> means, now that they share `Publisher`) wasn't re-run end-to-end.

### M-5. Unmapped NYT categories leak raw slugs into the reader UI

Per the CHANGELOG, excluding meta/classifieds NYT categories (`nyregion`, `jobs`,
`realestate`, `autos`, `obituaries`, …) from the nav was **deliberate** — but their articles
still ingest and display, and `NewsHelper#category_name` falls back to the raw English slug,
so a Persian reader sees a label like "nyregion" with the default red accent, and
`sections_by_category` sorts those sections last with an untranslated header. Either map the
excluded categories onto existing ones at the feed level (e.g. `nyregion → us`) or give
`category_name` a curated fallback so raw slugs never render.

### M-6. Ignore rules match anywhere in the string

[article.rb:21-38](app/models/article.rb#L21-L38) — `IGNORE_TITLE_PREFIXES` uses
`title.include?(prefix)` (not `start_with?`), so a headline like *“Ministers to Watch: …”*
is skipped; `IGNORE_URL_KEYWORDS` (`programmes`, `sounds`) substring-matches any URL
containing those words (e.g. a `/news/...tv-programmes...` article). Tighten to prefix/path
matching.

### M-7. Worker status server: unauthenticated, binds 0.0.0.0

[worker.rb:621-636](worker/worker.rb#L621-L636) — exposes task IDs, models, error messages
(which can include upstream text) to anyone who can reach the port. Default bind should be
`127.0.0.1`, with an opt-in env for LAN exposure and/or a static token query param.

### M-8. No data-retention story

Unbounded growth: `article_views` (a row per human/bot view), `search_queries`,
`versions` (PaperTrail on 7 models, full object YAML per edit), completed `tasks` (large
`requests`/`responses` JSON — entire article texts duplicated per attempt), `solid_cache_entries`
(self-trimming, OK). Add pruning rake tasks (`bbc:prune[days]`) for: views/searches older
than ~180 d (or roll up into daily aggregates), completed tasks older than ~30 d (keep
failed), versions older than ~1 y.

### M-9. Mass assignment of `role`/`active` (Brakeman finding)

[users_controller.rb:44-46](app/controllers/admin/users_controller.rb#L44-L46) — acceptable
because the controller is admin-only and the last-admin validation exists, but permit-lists
should still differ: an admin editing **their own** account shouldn't be able to demote/
deactivate themselves accidentally through the same form (the model guard only protects the
*last* admin). Low effort: `permit` conditionally, or ignore `role/active` when
`@user == current_user` unless another admin exists.

### M-10. Boot refuses to start without seed-only credentials

[required_env.rb](config/initializers/required_env.rb) — `ADMIN_USERNAME/PASSWORD/EMAIL`
are only consumed by `db:seed` when the users table is empty, yet **every** boot of an
already-seeded production app hard-fails without them. This forces keeping a bootstrap
password in the environment forever (a secret that should be retired after first boot).
Relax to a warning when `User.any?` (or only enforce in the seed task itself).

### M-11. No Content-Security-Policy; CDN assets on the admin

[content_security_policy.rb](config/initializers/content_security_policy.rb) is fully
commented out. The news layout added SRI for its CDN assets; verify the admin layout's
Bootstrap CDN tags carry SRI too, and enable a CSP (default-src 'self'; script/style with
nonces + the CDN host). The public site is a high-value defacement target given its topic.

### M-12. Telegram bot tokens stored in plaintext DB columns

`telegram_channels.token` — PaperTrail already excludes it, but the column itself is plain
text (and appears in DB backups). Rails 7+ Active Record encryption
(`encrypts :token, deterministic: false`) is a drop-in here.

### M-13. Bulk admin actions make serial external HTTP calls in-request

`bulk_prioritize` mirrors each change to llmarkt with one HTTP call per task
([tasks_controller.rb:60-81](app/controllers/admin/tasks_controller.rb#L60-L81), 15 s timeout
each); `bulk_rewrite`/`bulk_translate` submit each new task to llmarkt synchronously via
`after_create_commit`. Selecting 50 rows can hold the request for minutes. Move llmarkt
submission off the request thread (§7.3) or batch with a low per-call timeout.

### M-14. Repo hygiene: legacy artifacts confuse the entry path

Root contains the pre-Rails `update.rb`, `articles.db` (320 KB SQLite), `prompt`, `prompt2`
(superseded by DB prompts), `worker_design.md`, and **two** worker implementations
(`worker/` Ruby — documented; `worker-go/` — undocumented in the README). Decide which worker
is canonical, mark the other experimental/removed, and delete or move legacy files into
`docs/legacy/`. (`plan.md` line count is also getting unwieldy — see §9 note.)

### M-15. `OllamaServer.pick` always returns the first server/model

[ollama_server.rb:14-18](app/models/ollama_server.rb#L14-L18) — alphabetical first-match:
no round-robin, no load awareness, and the *order of names* silently determines which GPU
does all the work. Fine for one server; document it or add rotation when multiple exist.

---

## 5. Low priority / hygiene

| # | Issue | Where |
|---|---|---|
| L-1 | `Task` model mixes queue mechanics with orchestration (chaining, notifications, broadcasting) — 300+ lines | [task.rb](app/models/task.rb) |
| L-2 | `NewsController` is a fat controller: story-pool query logic, search, robots/llms text bodies inline | [news_controller.rb](app/controllers/news_controller.rb) |
| L-3 | Bilingual UI strings in a helper constant instead of Rails I18n (fine at this size; revisit if a 3rd locale ever lands) | [news_helper.rb:78-129](app/helpers/news_helper.rb#L78-L129) |
| L-4 | No system/browser tests; no coverage measurement; `worker/worker.rb` (702 lines) has zero tests | `test/` |
| L-5 | `sort_clause` + filter/count boilerplate duplicated across 5+ admin controllers | e.g. [articles_controller.rb:224-230](app/controllers/admin/articles_controller.rb#L224-L230) |
| L-6 | `robots`/`llms` heredocs in the controller; move to views/partials for editability | [news_controller.rb:94-204](app/controllers/news_controller.rb#L94-L204) |
| L-7 | `Translation.prompt_name` legacy magic strings (`"prompt"`, `"refine"`) — convert to an enum/constant | [task.rb:69](app/models/task.rb#L69) |
| L-8 | `manual_edit_review_count` COUNT on every admin page — cache with a short TTL or invalidate on flag change | [application_helper.rb:26-28](app/helpers/application_helper.rb#L26-L28) |
| L-9 | `stimulus-rails`/`importmap` scaffolding present but only a `hello_controller.js`; admin JS is inline in the layout — pick one approach | `app/javascript/` |
| L-10 | `Api::TasksController#complete` lets a worker complete a task it never claimed (single shared token makes this moot today; matters if per-worker tokens land — F-13) | [api/tasks_controller.rb](app/controllers/api/tasks_controller.rb) |

---

## 6. Code & logic improvements

### 6.1 Extract a task orchestrator

`Task#complete!`/`fail!`/chaining/notification/broadcast belong in a service
(`Tasks::Orchestrator` or per-kind handlers). Benefits: the model shrinks to queue
semantics (claim/requeue/stale), kind-specific behavior stops being a `case` ladder, and
C-4/H-5 fixes (transactions, idempotency guards) land in one place. Trade-off: one more
indirection layer; keep it a plain PORO with `run_completion(task, responses)`.

### 6.2 Query objects for the portal

`StoryPool.new(lang:, category:)` encapsulating `published_translations`,
latest-per-article (in SQL, H-6), EN-edition extras, and caching. `NewsController` becomes
thin, and the sitemap/search/homepage stop re-implementing overlapping variants of the same
query. Same pattern for the admin count/filter/sort boilerplate (L-5) as a `Filterable`
concern taking a whitelist hash.

### 6.3 One `Publisher` service for Telegram posting

Merge `Autoposter.deliver`, `TranslationsController#post_to_channel`,
`TelegramAdminNotifier#post_to_channel` (three near-identical create-post/send/update
sequences with subtly different error handling) into one service returning a result object.
Add the `(translation_id, telegram_channel_id)` unique index (M-4).

### 6.4 Shared LLM-response cleaning

One `LlmText.clean` (strip `<think>`, strip stray code fences, `strip`) used by rewriter/
translator/refiner/tagger (fixes H-9 and de-duplicates 3 copies of the regex).

### 6.5 Config module unification

`Llmarkt`, `MailerConfig`, `TelegramAdminBot`, `AdminBootstrap` each hand-roll
credentials-then-ENV lookup. Extract `CredentialConfig.fetch(:key, "ENV_NAME")`; each module
keeps its domain methods. Low value alone, but it makes M-10's policy change one-place.

### 6.6 Slug service

One `Slugger.call(text, scope:)` shared by `Article`/`Translation` implementing the
documented `-2/-3` strategy with `RecordNotUnique` retry (M-1).

### 6.7 Worker: extract + test

`worker/worker.rb` mixes config, state, HTTP, task processing, and an HTML dashboard in one
script. Split into `worker/lib/*.rb` (still stdlib-only, still one process) so
`process_task`, placeholder substitution, and claim/fail flows get unit tests. Decide the
fate of `worker-go/` (M-14) — two implementations means every task-API change needs two
patches (the Go worker likely already lags the `models[]` behavior).

### 6.8 Test-suite depth

Green ≠ covering the risky paths. The llmarkt double-execution race (C-4), pool exhaustion
(H-4), and Telegram Markdown failures (H-8) were all invisible to the suite. Add:
- clock-travel tests around `STALE_AFTER` interplay with llmarkt submission;
- a request test asserting disabled users are logged out (C-1);
- WebMock-level tests for Telegram escaping with hostile titles (`*_[`);
- property-style tests for `Slugger` and `gregorian_to_jalali` (round-trip a known table).

---

## 7. Architecture & design assessment

### 7.1 What's sound

- **Pull-queue + webhook duality** is a genuinely good design: the app stays deployable on a
  cheap host; GPU workers are stateless clients; llmarkt is additive, not a rewrite. The
  fallback semantics (submission failure ⇒ stays `pending` for the worker) are elegant.
- **Provenance** (prompt versions → tasks → outputs, PaperTrail on content) gives editorial
  accountability most CMSes lack.
- **Separation of editions** via `(:lang)` scope + helper accessors is clean and SEO-correct
  (hreflang, canonical, JSON-LD were done properly).

### 7.2 Structural risks

1. **The cache is being used as a database** (tags, featured picks, og:images, story pool).
   Solid Cache is *in the primary DB* anyway — the "no schema change" benefit is only
   avoiding a migration, while costing durability, queryability, and cold-start correctness.
   Persist derived editorial data; cache only recomputables. (M-3, H-4, H-6)
2. **Public request path does third-party I/O** (geo HTTP, og:image fetch) and
   **unauthenticated writes** (views, searches, priority bumps). A news site's read path
   should be: SQL (indexed) → fragment cache → HTML. Everything else belongs to ingest time
   or background work. (H-1, H-4, H-7)
3. **No in-app background executor.** Solid Queue was deliberately removed, which was right
   for LLM work — but the app now has a growing class of *non-LLM* async needs (feed ingest,
   geo lookups, image resolution, llmarkt HTTP, retention pruning) squeezed into request
   threads or cron. **Recommendation:** reintroduce a minimal Solid Queue (it's DB-backed,
   zero new infra, runs in-Puma via the supervisor) *only* for these I/O jobs, keeping the
   Task queue exclusively for LLM work. Alternative: add non-LLM kinds to `Task` — but that
   couples unrelated concerns to the worker protocol and admin queue UI. (§3 H-1/2/4, M-13)
4. **Article-level scalar status** conflicts with the many-outputs model (M-2).
5. **Dual worker implementations** without a declared owner (M-14/6.7).

### 7.3 Decision to make (blocking several fixes)

> **Where does non-LLM background work run?**
> Options: (a) Solid Queue in-Puma — recommended; (b) more cron rake tasks — no retries,
> no per-job visibility; (c) `Thread.new` fire-and-forget — loses work on deploy, no retry;
> (d) overload `Task` — protocol pollution.
> H-1, H-2, H-4, M-13, and M-8 all want (a).

---

## 8. Proposed new features

Ordered by value-for-effort. Effort: **L** ≤ 1 day · **M** ≈ 2–4 days · **H** ≈ 1–2 weeks.

| # | Feature | Value | Effort | Approach / dependencies |
|---|---|---|---|---|
| F-1 | **RSS/Atom + JSON Feed for the portal** (fa + en, per-category) | High — distribution, Telegram/RSS readers, LLM crawlers; trivially cacheable | **L** | New `news#feed` actions reusing `StoryPool`; `<link rel="alternate">`; extend sitemap/llms.txt |
| F-2 | **Pipeline health monitoring & alerting** — admin banner + Telegram-admin-bot alert when: pending > N for T minutes, no worker poll in T, llmarkt error rate spike, feed fetch failing repeatedly | High — today a dead worker is only noticed by absence of news | **L–M** | Cron task computing health snapshot into a table/cache + reuse `TelegramAdminBot`; extend `/up` with a queue-health JSON endpoint (token-gated) |
| F-3 | **Persist tags + public tag pages** (`/tag/:tag`) with related-stories module on articles | High — SEO surface area, internal linking, fixes M-3 | **M** | `tags`/`article_tags` tables backfilled from cache; tag chips link to tag page; "related stories" = same tags ∩ recent |
| F-4 | **Proper full-text search** (PG `tsvector` + `pg_trgm` for fa/en; SQLite FTS5 in dev) | High — LIKE search misses Persian morphology and won't scale | **M** | Generated tsvector columns + GIN index; normalize Persian (ي→ی, ك→ک, ZWNJ) at index & query time; keep `SearchQuery` analytics |
| F-5 | **Email digest newsletter** (daily/weekly top stories) | Medium-High — retention channel; Resend already wired | **M** | `subscribers` table + double-opt-in + unsubscribe token; digest = `FeaturedSelector` output; cron `bbc:digest` |
| F-6 | **Telegram posts with images** (`sendPhoto` using the article image + HTML caption) | Medium — much higher engagement on channels | **L** | Depends on H-8 (escaping) + H-4 (persisted image_url); fallback to text when no image |
| F-7 | **Editorial diff view** — side-by-side + word-level diff between translation versions and against the refine source | Medium — makes the manual-edit workflow actually pleasant | **L–M** | PaperTrail data already exists; add `diff-lcs` gem; render inline in the existing history panels |
| F-8 | **LLM quality-review task kind** — after refine, a `review` task scores fluency/faithfulness (1–10 + reasons); low scores auto-set `needs_manual_edit` and surface on the dashboard | High — closes the loop the manual-edit flag started; catches bad machine output before readers | **M–H** | New `Task` kind + `Prompt` slot + score columns on translations; thresholds configurable; feeds F-2 dashboard |
| F-9 | **Web push notifications for breaking news** (PWA manifest already exists) | Medium | **M** | `web-push` gem + service-worker subscribe; admin "push this story" button + auto for `top` category; needs VAPID keys |
| F-10 | **Image self-hosting/proxy** — download og:image to ActiveStorage, serve resized WebP | Medium — stops hotlinking BBC/NYT (fragile + leaks reader IPs to origin), enables real CDN caching | **M** | ActiveStorage (DB service or S3-compatible); variant generation; ties into H-4's ingest-time resolution |
| F-11 | **Public analytics opt-out & privacy page** + IP truncation | Medium — the site logs per-IP geo; a privacy page is table stakes for a news property | **L** | Truncate IPs before geolocation (drop last octet), static page, retention doc (with M-8) |
| F-12 | **Error tracking** (Sentry or Honeybadger) | Medium — dozens of `rescue → Rails.logger` sites currently vanish into stdout | **L** | Add gem + DSN credential; wire the swallowed-rescue sites through `Sentry.capture_exception` |
| F-13 | **Per-worker API tokens** with names, last-seen, revocation (admin CRUD) | Low-Medium — needed once >1 worker machine exists | **M** | `worker_tokens` table; `Api::BaseController` looks up token; last-seen powers F-2 |
| F-14 | **Scheduled publishing / embargo** on translations | Low | **M** | `publish_at` column; story pool filters `publish_at <= now`; admin datetime field |
| F-15 | **Reader-side theme toggle (dark mode) for the portal** | Low | **L** | CSS custom properties already in place for category colors; add `prefers-color-scheme` + toggle |

---

## 9. Metrics & validation

**Security / correctness gates (CI):**
- `bin/rails test` (grow past 394: add the C-1/C-4/H-8 regression tests from §6.8).
- `bundle exec brakeman -q --exit-on-warn` (baseline: 1 known medium → 0 after M-9).
- `bundle exec rubocop`.
- Add `bundler-audit` (gem CVEs) — currently absent.
- Coverage: add SimpleCov; baseline, then ratchet (target ≥ 85 % lines on `app/`).

**Performance benchmarks (before/after Phase 2):**
- Homepage & article-page TTFB p50/p95 with warm and **cold** cache (`ab`/`oha`, 50 concurrent)
  — expect the cold-cache article page to drop from "seconds (og:image + geo fetches)" to
  "<100 ms" once H-1/H-4 land.
- `EXPLAIN ANALYZE` on `published_translations` latest-per-article before/after H-6/H-10 on a
  production-sized dataset (generate 50k translations in a seed script).
- Task throughput: time for 100 queued tasks with 4 workers before/after H-12 (SKIP LOCKED).
- DB growth: rows/day on `article_views`, `versions`, `tasks` before/after M-8 pruning.

**Operational metrics (F-2 dashboard):**
- Queue depth by status/kind, oldest-pending age, worker last-poll age, llmarkt error rate,
  feed-fetch failure count, Telegram send failures — alert thresholds on each.

**Validation protocol per fix:** each Critical/High item ships with (1) a failing test first
where feasible, (2) a manual smoke check documented in the PR/CHANGELOG (the project already
has this habit — keep it), (3) no new Brakeman warnings.

---

## 10. Phased roadmap

### Phase 0 — Security hardening (≈ 1 day, ship immediately) — ✅ DONE (2026-07-16)
C-1 (active-user session check) → C-2 (`reset_session`) → C-5 (remove `null_session`) →
C-3 (rate limits) → C-6 (`config.hosts`) → H-13 (`allow_browser` scope).
All are near-one-liners with tests; zero migration risk.

**Implementation status:**
- All six items shipped: `app/controllers/application_controller.rb`,
  `app/controllers/admin/sessions_controller.rb`,
  `app/controllers/admin/password_resets_controller.rb`,
  `app/controllers/admin/translations_controller.rb`,
  `app/controllers/admin/rewrites_controller.rb`, `app/controllers/admin/base_controller.rb`,
  `config/environments/production.rb`. New regression test added in
  `test/controllers/admin/sessions_controller_test.rb` (C-1: disabled user with a live
  session gets redirected to login).
- Found and fixed one thing this document missed: `Admin::RewritesController` had the
  same `protect_from_forgery with: :null_session` leftover as
  `Admin::TranslationsController` (C-5) — folded into the same fix.
- C-3's rate limits cover the login and password-reset endpoints only; the
  `GET /search` write-per-request part of C-3 is left for H-7 (Phase 2) since it's a
  bot/analytics-abuse concern rather than an authentication brute-force one.
- 395 tests green (was 394), `rubocop`/`zeitwerk:check` clean, Brakeman unchanged (still
  the 1 known M-9 warning). No migrations, nothing else touched.
- **Not done in this pass:** everything in Phases 1–4, including C-4 (the
  llmarkt/stale-reclaim duplicate-execution race) and H-5 (non-atomic `complete!`), which
  are the next-highest-risk items per §10.

### Phase 1 — Pipeline reliability (≈ 1 week) — ✅ DONE (2026-07-16)
C-4 (stale/llmarkt race: STALE_AFTER, `external_job_id` hygiene, callback locking,
idempotent complete) → H-5 (transactional `complete!`) → H-8 (Telegram escaping) →
H-9 (translator `<think>` strip) → H-3 (feed timeouts) → H-12 (SKIP LOCKED) →
H-11 (Solid Cable) → M-4 (single Publisher + unique index).
*Exit criteria:* chaos test — kill the worker mid-task, let llmarkt time out, replay
duplicate webhooks — with no duplicate tasks/posts and no wrongly-failed targets.

**Implementation status:**
- All eight items shipped — see the "Implementation note (2026-07-16)" under
  each of C-4, H-3, H-5, H-8, H-9, H-11, H-12, and M-4 above for exactly what
  changed and file references, and the CHANGELOG entry "Fixed — Phase 1
  pipeline reliability from plan2.md (C-4, H-5, H-8, H-9, H-3, H-12, H-11,
  M-4)" for the consolidated summary.
- New files: `app/services/llm_text.rb` (H-9), `app/services/publisher.rb`
  (M-4). New migrations (not run, per project rules — `db/schema.rb` updated
  by hand instead): `20260716000001_add_unique_index_to_telegram_posts.rb`,
  `20260716000002_create_solid_cable_messages.rb`.
- 395 tests green (2 updated for the HTML parse-mode switch, 1 new escaping
  test, 1 stale tautological test removed — see CHANGELOG). `rubocop`/
  `zeitwerk:check` clean. Brakeman unchanged (still the 1 known M-9 warning).
- **Exit criteria not met as originally scoped:** no actual chaos test was
  run (a live worker-kill + llmarkt-timeout + duplicate-webhook-replay
  scenario). Each fix was verified individually — full test suite, plus a
  scripted `bin/rails runner` smoke check exercising `complete!`
  transactionality/idempotency and `requeue!` clearing `external_job_id` —
  but not under an actually induced race between the two backends. Treat
  C-4 as *believed* fixed, not *proven* fixed under load.
- **Not done in this pass:** llmarkt job cancellation on reclaim (no such
  endpoint in the vendor API today); H-3's `Down`-style max-size guard and
  H-2 (async feed ingest) remain Phase 2 work; M-4's full semantic-divergence
  re-audit across all `autopost` paths wasn't re-run (see the M-4 note
  above — the specific issue it originally flagged had already been
  superseded before this review). Everything in Phases 2–4 is still
  unstarted.

### Phase 2 — Public-path performance & data model (≈ 1–2 weeks)
Decision §7.3 (adopt Solid Queue for non-LLM I/O) → H-1 (geo off the request path, CDN
headers first) → H-4 + persisted `image_url` (ingest-time image resolution) → H-2 (async
feed ingest) → H-6 (SQL latest-per-article + capped pool + sitemap pagination) →
H-7 (bot filtering, priority clamp) → H-10 (indexes) → M-8 (retention pruning) →
M-1 (slugs) → M-3 (persist tags/featured — enables F-3).

### Phase 3 — High-value features (≈ 2–3 weeks, re-prioritize with product goals)
F-1 (feeds) → F-2 (health monitoring) → F-3 (tag pages + related stories) →
F-6 (Telegram images) → F-12 (error tracking) → F-4 (full-text search) → F-8 (LLM review).

### Phase 4 — Quality & polish (ongoing)
§6 refactors (orchestrator, StoryPool, Filterable concern, worker split/tests) →
M-2 (article status derivation) → M-5/M-6 (category map, ignore rules) → M-7/M-11/M-12
(status-page auth, CSP, token encryption) → M-14 (repo cleanup, single worker) →
F-5/F-9/F-10/F-11 → L-items opportunistically alongside adjacent work.

---

*End of plan. No code, schema, or configuration was modified in producing this document.*
