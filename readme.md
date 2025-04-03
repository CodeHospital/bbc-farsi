


BC Farsi News Bot

A Ruby application that fetches BBC News articles, translates them to Farsi, and posts them to a Telegram channel.

## Features

- Fetches latest news articles from BBC News using the News API
- Translates articles from English to Farsi using LibreTranslate
- Posts translated articles with their original text to a Telegram channel
- Includes article images when available
- Tracks previously posted articles to avoid duplicates
- Runs as a Docker container with scheduled updates

## Prerequisites

- News API key (from [newsapi.org](https://newsapi.org/))
- Telegram Bot Token (from [BotFather](https://t.me/botfather))
- Telegram Channel name
- LibreTranslate URL and API key (if required)

## Setup

### Manual Setup

1. Install required gems:
   ```
   gem install news-api telegram-bot-ruby httparty sqlite3 dotenv
   ```

2. Copy `.env.example` to `.env` and fill in your credentials:
   ```
   cp .env.example .env
   ```

3. Run the script:
   ```
   ruby update.rb
   ```

### Docker Setup

1. Build the Docker image:
   ```
   docker build -t bbcfarsi .
   ```

2. Run the container:
   ```
   docker run -d --name bbcfarsi --restart always bbcfarsi
   ```

## Environment Variables

- `NEWS_API_KEY`: Your API key from News API
- `TELEGRAM_BOT_TOKEN`: Your Telegram bot token
- `TELEGRAM_CHANNEL`: Your Telegram channel (format: @YourChannelName)
- `LIBRETRANSLATE_URL`: URL for LibreTranslate API
- `LIBRETRANSLATE_API_KEY`: API key for LibreTranslate (if required)

## How It Works

1. The script fetches the latest BBC News articles
2. It checks if articles have been previously posted (using a SQLite database)
3. New articles are translated from English to Farsi
4. The translated articles (along with original text) are posted to the Telegram channel
5. When running in Docker, this process repeats every 10 minutes

## License

This project is licensed under the MIT License.
