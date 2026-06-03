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
- `ArticleRewriter` — calls Qwen3 14B via Ollama, strips `<think>` tags
- `ArticleTranslator` — calls aya-expanse:32b via Ollama with prompt file
- `TelegramPoster` — sends translated message to a channel

### Background Jobs (Solid Queue)
- `FetchFeedsJob` — fetch all enabled feeds, upsert Articles
- `RewriteArticleJob(article_id)` — rewrite one article, create Rewrite
- `TranslateArticleJob(rewrite_id)` — translate one Rewrite, create Translation
- `AutopostJob` — find completed Translations not posted to autopost channels, post them

### Cron (Solid Queue recurring tasks)
- Every 30 min: `FetchFeedsJob`
- Every 5 min: `AutopostJob`

### Admin (HTTP Basic Auth)
- `/admin` — dashboard (counts, recent activity)
- `/admin/feeds` — CRUD, enable/disable toggle
- `/admin/articles` — list (filter by feed/status), show, trigger rewrite
- `/admin/rewrites` — list, show, edit content, rerun
- `/admin/translations` — list, show, edit title/body, post to channel, enable autopost
- `/admin/telegram_channels` — CRUD, enable/disable, autopost toggle

### Tech Stack
- Rails 8, SQLite3
- Solid Queue (jobs + recurring cron)
- Bootstrap 5 CDN (admin UI)
- dotenv-rails (.env loading)
- feedjira + httparty (RSS)
- ollama-ai (LLM)
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
