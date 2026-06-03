# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
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
