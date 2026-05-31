# frozen_string_literal: true

# Install required gems:
# gem install news-api telegram-bot-ruby httparty sqlite3 dotenv ollama-ai

require 'news-api'
require 'telegram/bot'
# require 'httparty'
# require 'json'
require 'sqlite3'
require 'dotenv'
require 'ollama-ai'
require 'openssl'

# Load environment variables from .env file
Dotenv.load('.env')

# Configuration
NEWS_API_KEY = ENV['NEWS_API_KEY'] # Replace with your NewsAPI key
TELEGRAM_BOT_TOKEN = ENV['TELEGRAM_BOT_TOKEN'] # Replace with your Telegram bot token
TELEGRAM_CHANNEL = ENV['TELEGRAM_CHANNEL'] # Replace with your channel (e.g., @MyNewsChannel)
OLLAMA_URL = ENV['OLLAMA_URL'] || 'http://192.168.1.12:11434' # Ollama server address
OLLAMA_MODELS = ['aya-expanse:32b'].freeze # , 'gemma3:27b', 'qwen3:14b', 'aya:8b'].freeze # , 'mistral-nemo', 'llama3.2'

# Validate required environment variables
required_env_vars = %w[NEWS_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_CHANNEL]
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
    description TEXT,
    translated_title TEXT,
    translated_description TEXT,
    sent_at DATETIME
  );
SQL

# Configure OpenSSL to handle SSL certificates properly
# This resolves "unable to get certificate CRL" errors on macOS
cert_store = OpenSSL::X509::Store.new
cert_store.set_default_paths
# Don't check CRL (Certificate Revocation List) to avoid SSL errors
cert_store.flags = 0
OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE = cert_store

# Initialize NewsAPI with olegmikhnovich's gem
news_api = News.new(NEWS_API_KEY)

top_headlines = news_api.get_top_headlines(sources: 'bbc-news', language: 'en')
# pp top_headlines
# Fetch BBC news using the 'everything' endpoint
response = news_api.get_everything(
  sources: 'bbc-news',  # BBC News source ID
  language: 'en',       # English news
  pageSize: 35 # Fetch 25 articles (note camelCase per gem docs)
)

# Initialize Telegram bot
bot = Telegram::Bot::Client.new(TELEGRAM_BOT_TOKEN)

# Initialize Ollama client
@client = Ollama.new(
  credentials: { address: OLLAMA_URL },
  options: { server_sent_events: true }
)
prompts = [File.read('prompt')] # , File.read('prompt2')]

def translate_with(text, prompt, model)
  translate_response = @client.chat(
    {
      model:,
      messages: [
        {
          role: 'system',
          content: prompt
        },
        {
          role: 'user',
          content: text
        }
      ],
      stream: false
    }
  )
  pp "translate_response: #{translate_response}"
  # Ollama returns an array of responses, get the last complete message
  translate_response.last.dig('message', 'content')
end

puts "Fetched #{response.size} articles from BBC News. Processing and posting to Telegram channel #{TELEGRAM_CHANNEL}..."
# Process and post each article
response.each do |article|
  # Original English text
  if article.content == article.description
    # puts "Skipping article with same content and description: #{article.title}"
    next
  end

  ignore_list = ['Watch:', 'Assignment:', 'Speak:', 'Podcast:', 'Newsletter:', 'Trending:']
  if ignore_list.any? { |word| article.title.include?(word) }
    puts "Skipping article with ignore list word: #{article.title}"
    next
  end
  if %w[iplayer programmes sounds].any? { |word| article.url.include?(word) }
    puts "Skipping article with ignore list word: #{article.title}"
    next
  end
  # Skip if article has already been sent
  exists = db.get_first_value('SELECT 1 FROM articles WHERE url = ?', article.url)
  if exists
    puts "Skipping already sent article: #{article.title}"
    next
  end

  prompts.each_with_index do |prompt, prompt_index|
    OLLAMA_MODELS.each do |model|
      # Translate to Persian using Ollama
      begin
        translated_title = translate_with(article.title, prompt, model)
        translated_description = translate_with("#{article.description}\n\n#{article.content}", prompt, model)
        if translated_title.nil? || translated_title.empty? || translated_description.nil? || translated_description.empty?
          puts "Error: Empty translation response for '#{article.title}'"
          next
        end
      rescue StandardError => e
        puts "Translation failed for '#{article.title}': #{e.message}"
        pp e.backtrace
        next
      end

      # Construct message
      message = "📢 *#{translated_title}*\n\n#{translated_description}\n\n\n#{article.url}\n\nfollow @realbbcfarsi for more\n\n*#{article.title}*"
      if OLLAMA_MODELS.size > 1 || prompts.size > 1
        message += "\n\n_Translation prompt: #{prompt_index + 1}, Model: #{model}_"
      end

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
      begin
        db.execute(
          'INSERT INTO articles (url, title, description, translated_title, translated_description, sent_at) VALUES (?, ?, ?, ?, ?, datetime("now"))', [
            article.url, article.title, article.description, translated_title, translated_description
          ]
        )
      rescue StandardError
        nil
      end

      puts "Posted: #{translated_title}"
    end
  end
  sleep 2 # Avoid Telegram rate limits
end

puts 'Done posting news to Telegram!'
