source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.5"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Databases: SQLite in development/test, PostgreSQL in production (DATABASE_URL).
# See the `:development, :test` and `:production` groups below.
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# BBC news fetching
gem "feedjira", "~> 4.0"
gem "httparty", "~> 0.24.0"

# Telegram bot
gem "telegram-bot-ruby", "~> 2.4"

# Env vars
gem "dotenv-rails", "~> 2.8"

# Pagination
gem "pagy", "~> 43.6.0"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Tracks who changed what and keeps a full version history of edited records
# (Rewrites, Translations, Feeds, Telegram channels, Ollama servers, Users).
gem "paper_trail"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Database-backed cache store (Rails.cache). Background work is handled by an
# external worker client over the task API, not an in-app job queue.
gem "solid_cache"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# PostgreSQL is the production database (connected via DATABASE_URL).
group :production do
  gem "pg", "~> 1.5"
end

group :development, :test do
  # SQLite for local development and the test suite.
  gem "sqlite3", ">= 2.1"

  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "minitest", "~> 5.0"
  gem "webmock", "~> 3.0"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
