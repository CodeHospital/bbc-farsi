# frozen_string_literal: true

# Install required gems:
# gem install news-api telegram-bot-ruby httparty sqlite3 dotenv ruby-openai

require 'news-api'
require 'telegram/bot'
require 'httparty'
require 'json'
require 'sqlite3'
require 'dotenv'
require 'openai'

# Load environment variables from .env file
Dotenv.load

# Configuration
NEWS_API_KEY = ENV['NEWS_API_KEY'] # Replace with your NewsAPI key
TELEGRAM_BOT_TOKEN = ENV['TELEGRAM_BOT_TOKEN'] # Replace with your Telegram bot token
TELEGRAM_CHANNEL = ENV['TELEGRAM_CHANNEL'] # Replace with your channel (e.g., @MyNewsChannel)
OPENAI_API_KEY = ENV['OPENAI_API_KEY'] # API key for OpenAI

# Validate required environment variables
required_env_vars = %w[NEWS_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_CHANNEL OPENAI_API_KEY]
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

# Initialize OpenAI client
client = OpenAI::Client.new(access_token: OPENAI_API_KEY)

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

  # Translate to Persian using OpenAI
  begin
    translate_response = client.chat(
      parameters: {
        model: "babbage-002",
        messages: [{
          role: "system",
          content: "You are a professional English to Persian translator. Translate the following texts keeping the meaning and tone intact. Return only the translations separated by ||| without any additional text."
        }, {
          role: "user",
          content: "#{article.title}\n#{article.description}"
        }]
      }
    )
    
    translations = translate_response.dig("choices", 0, "message", "content").split('|||')
    translated_title = translations[0].strip
    translated_description = translations[1].strip
  rescue StandardError => e
    puts "Translation failed for '#{article.title}': #{e.message}"
    next
  end

  # Construct message
  message = "📢 *#{translated_title}*\n\n#{translated_description}\n\n#{article.url}\n\n\n*#{article.title}*\n\n#{article.description}"
pp messages
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
