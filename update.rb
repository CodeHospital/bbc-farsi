# frozen_string_literal: true

# Install required gems:
# gem install news-api telegram-bot-ruby httparty sqlite3 dotenv

require 'news-api'
require 'telegram/bot'
require 'httparty'
require 'json'
require 'sqlite3'
require 'dotenv'

# Load environment variables from .env file
Dotenv.load

# Configuration
NEWS_API_KEY = ENV['NEWS_API_KEY'] # Replace with your NewsAPI key
TELEGRAM_BOT_TOKEN = ENV['TELEGRAM_BOT_TOKEN'] # Replace with your Telegram bot token
TELEGRAM_CHANNEL = ENV['TELEGRAM_CHANNEL'] # Replace with your channel (e.g., @MyNewsChannel)
LIBRETRANSLATE_URL = ENV['LIBRETRANSLATE_URL'] # Public instance; swap if self-hosted
LIBRETRANSLATE_API_KEY = ENV['LIBRETRANSLATE_API_KEY'] # API key for LibreTranslate

# Validate required environment variables
required_env_vars = %w[NEWS_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_CHANNEL LIBRETRANSLATE_URL]
required_env_vars.each do |var|
  raise "Missing required environment variable: #{var}" if ENV[var].nil? || ENV[var].empty?
end

# Initialize SQLite database
db = SQLite3::Database.new 'articles.db'

# Create articles table if it doesn't exist
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS articles (
    url TEXT PRIMARY KEY,
    title TEXT,
    sent_at DATETIME
  );
SQL

# Initialize NewsAPI with olegmikhnovich's gem
news_api = News.new(NEWS_API_KEY)

top_headlines = news_api.get_top_headlines(sources: 'bbc-news', language: 'en')
# pp top_headlines
# Fetch BBC news using the 'everything' endpoint
response = news_api.get_everything(
  sources: 'bbc-news',  # BBC News source ID
  language: 'en',       # English news
  pageSize: 15 # Fetch 5 articles (note camelCase per gem docs)
)

# Initialize Telegram bot
bot = Telegram::Bot::Client.new(TELEGRAM_BOT_TOKEN)

# Process and post each article
response.each do |article|
  # Skip if article has already been sent
  exists = db.get_first_value('SELECT 1 FROM articles WHERE url = ?', article.url)
  if exists
    puts "Skipping already sent article: #{article.title}"
    next
  end

  # Original English text
  next if article.content == article.description

  # Translate to Persian using local LibreTranslate
  translate_response = HTTParty.post(
    LIBRETRANSLATE_URL,
    body: {
      q: [article.title, article.description], # Array to translate both at once
      source: 'en',
      target: 'fa', # Persian (Farsi)
      format: 'text',
      api_key: LIBRETRANSLATE_API_KEY
    }.to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

  # Parse translated text
  if translate_response.success?
    translations = JSON.parse(translate_response.body)['translatedText']
    translated_title = translations[0]
    translated_description = translations[1]
  else
    pp translate_response
    puts "Translation failed for '#{article.title}': #{translate_response.body}"
    next # Skip this article if translation fails
  end

  # Construct message
  message = "📢 *#{translated_title}*\n\n#{translated_description}\n\n#{article.url}\n\n\n*#{article.title}*\n\n#{article.description}"

  # Post to Telegram channel with photo if available
  if article.urlToImage
    begin
      bot.api.send_photo(
        chat_id: TELEGRAM_CHANNEL,
        photo: article.urlToImage,
        caption: message,
        parse_mode: 'Markdown' # Enables bold title with *
      )
    rescue StandardError => e
      puts "Failed to send photo: #{e.message}. Sending text-only message."
      bot.api.send_message(
        chat_id: TELEGRAM_CHANNEL,
        text: message,
        parse_mode: 'Markdown'
      )
    end
  else
    bot.api.send_message(
      chat_id: TELEGRAM_CHANNEL,
      text: message,
      parse_mode: 'Markdown'
    )
  end

  # Store the article in database after successful sending
  db.execute('INSERT INTO articles (url, title, sent_at) VALUES (?, ?, datetime("now"))',
             [article.url, article.title])

  puts "Posted: #{translated_title}"
  sleep 2 # Avoid Telegram rate limits
end

puts 'Done posting news to Telegram!'
