# frozen_string_literal: true

# Install required gems:
# gem install feedjira httparty telegram-bot-ruby sqlite3 dotenv ollama-ai

require 'feedjira'
require 'httparty'
require 'telegram/bot'
require 'sqlite3'
require 'dotenv'
require 'ollama-ai'
require 'openssl'

Dotenv.load('.env')

TELEGRAM_BOT_TOKEN = ENV['TELEGRAM_BOT_TOKEN']
TELEGRAM_CHANNEL   = ENV['TELEGRAM_CHANNEL']
OLLAMA_URL         = ENV['OLLAMA_URL'] || 'http://192.168.1.12:11434'
OLLAMA_MODELS      = ['aya-expanse:32b'].freeze

BBC_FEEDS = {
  top:        'https://feeds.bbci.co.uk/news/rss.xml',
  world:      'https://feeds.bbci.co.uk/news/world/rss.xml',
  uk:         'https://feeds.bbci.co.uk/news/uk/rss.xml',
  business:   'https://feeds.bbci.co.uk/news/business/rss.xml',
  technology: 'https://feeds.bbci.co.uk/news/technology/rss.xml',
  science:    'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml',
  health:     'https://feeds.bbci.co.uk/news/health/rss.xml'
}.freeze

ACTIVE_FEEDS = %i[top world uk business technology science health].freeze

IGNORE_TITLE_PREFIXES = %w[Watch: Assignment: Speak: Podcast: Newsletter: Trending:].freeze
IGNORE_URL_KEYWORDS   = %w[iplayer programmes sounds].freeze

required_env_vars = %w[TELEGRAM_BOT_TOKEN TELEGRAM_CHANNEL]
required_env_vars.each do |var|
  raise "Missing required environment variable: #{var}" if ENV[var].nil? || ENV[var].empty?
end

# Resolve "unable to get certificate CRL" SSL errors on macOS
cert_store = OpenSSL::X509::Store.new
cert_store.set_default_paths
cert_store.flags = 0
OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE = cert_store

db = SQLite3::Database.new 'articles.db'
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

bot     = Telegram::Bot::Client.new(TELEGRAM_BOT_TOKEN)
@client = Ollama.new(
  credentials: { address: OLLAMA_URL },
  options: { server_sent_events: true }
)
prompts = [File.read('prompt')]

def fetch_bbc_articles(feed_keys)
  articles = []
  feed_keys.each do |feed_key|
    begin
      feed_url = BBC_FEEDS.fetch(feed_key)
      xml      = HTTParty.get(feed_url).body
      feed     = Feedjira.parse(xml)
      feed.entries.each do |entry|
        articles << {
          title:       entry.title,
          url:         entry.url,
          description: entry.summary,
          published:   entry.published
        }
      end
    rescue StandardError => e
      puts "Failed to fetch BBC feed '#{feed_key}': #{e.message}"
    end
  end
  articles.uniq { |article| article[:url] }
end

def translate_with(text, prompt, model)
  translate_response = @client.chat(
    {
      model:,
      messages: [
        { role: 'system', content: prompt },
        { role: 'user',   content: text }
      ],
      stream: false
    }
  )
  pp "translate_response: #{translate_response}"
  translate_response.last.dig('message', 'content')
end

articles = fetch_bbc_articles(ACTIVE_FEEDS)
puts "Fetched #{articles.size} unique articles from BBC RSS feeds. Posting to Telegram channel #{TELEGRAM_CHANNEL}..."

articles.each do |article|
  if IGNORE_TITLE_PREFIXES.any? { |prefix| article[:title].to_s.include?(prefix) }
    puts "Skipping article with ignored title prefix: #{article[:title]}"
    next
  end

  if IGNORE_URL_KEYWORDS.any? { |keyword| article[:url].to_s.include?(keyword) }
    puts "Skipping article with ignored URL keyword: #{article[:title]}"
    next
  end

  exists = db.get_first_value('SELECT 1 FROM articles WHERE url = ?', article[:url])
  if exists
    puts "Skipping already sent article: #{article[:title]}"
    next
  end

  prompts.each_with_index do |prompt, prompt_index|
    OLLAMA_MODELS.each do |model|
      begin
        translated_title       = translate_with(article[:title], prompt, model)
        translated_description = translate_with(article[:description].to_s, prompt, model)

        if translated_title.nil? || translated_title.empty? || translated_description.nil? || translated_description.empty?
          puts "Error: Empty translation response for '#{article[:title]}'"
          next
        end
      rescue StandardError => e
        puts "Translation failed for '#{article[:title]}': #{e.message}"
        pp e.backtrace
        next
      end

      message = "📢 *#{translated_title}*\n\n#{translated_description}\n\n\n#{article[:url]}\n\nfollow @realbbcfarsi for more\n\n*#{article[:title]}*"
      message += "\n\n_Translation prompt: #{prompt_index + 1}, Model: #{model}_" if OLLAMA_MODELS.size > 1 || prompts.size > 1

      bot.api.send_message(
        chat_id:    TELEGRAM_CHANNEL,
        text:       message,
        parse_mode: 'Markdown'
      )

      begin
        db.execute(
          'INSERT INTO articles (url, title, description, translated_title, translated_description, sent_at) VALUES (?, ?, ?, ?, ?, datetime("now"))',
          [article[:url], article[:title], article[:description], translated_title, translated_description]
        )
      rescue StandardError
        nil
      end

      puts "Posted: #{translated_title}"
    end
  end

  sleep 2
end

puts 'Done posting news to Telegram!'
