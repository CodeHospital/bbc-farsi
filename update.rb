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
OLLAMA_MODELS      = [ 'aya-expanse:32b' ].freeze
REWRITE_MODEL      = 'qwen3:14b'

REWRITE_SYSTEM_PROMPT = <<~PROMPT.strip
  You are a news editor. Given a BBC news article title and its summary, rewrite the body as a
  clear, self-contained paragraph in plain English. Expand any abbreviations, add brief factual
  context where helpful, and make it easy to understand for a general international audience.
  Output only the rewritten article text — no headings, no metadata, no commentary.
PROMPT

BBC_FEEDS = {
  top: 'https://feeds.bbci.co.uk/news/rss.xml',
  world: 'https://feeds.bbci.co.uk/news/world/rss.xml',
  uk: 'https://feeds.bbci.co.uk/news/uk/rss.xml',
  business: 'https://feeds.bbci.co.uk/news/business/rss.xml',
  technology: 'https://feeds.bbci.co.uk/news/technology/rss.xml',
  science: 'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml',
  health: 'https://feeds.bbci.co.uk/news/health/rss.xml'
}.freeze

ACTIVE_FEEDS          = %i[top world uk business technology science health].freeze
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

@db      = SQLite3::Database.new 'articles.db'
@bot     = Telegram::Bot::Client.new(TELEGRAM_BOT_TOKEN)
@client  = Ollama.new(credentials: { address: OLLAMA_URL }, options: { server_sent_events: true })
@prompts = [ File.read('prompt') ]

@db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS articles (
    url TEXT PRIMARY KEY,
    title TEXT,
    description TEXT,
    translated_title TEXT,
    translated_description TEXT,
    sent_at DATETIME
  );
SQL

def parse_feed_entries(feed_key)
  xml = HTTParty.get(BBC_FEEDS.fetch(feed_key)).body
  Feedjira.parse(xml).entries.map do |entry|
    { title: entry.title, url: entry.url, description: entry.summary, published: entry.published }
  end
rescue StandardError => e
  puts "Failed to fetch BBC feed '#{feed_key}': #{e.message}"
  []
end

def fetch_bbc_articles(feed_keys)
  feed_keys.flat_map { |key| parse_feed_entries(key) }
           .uniq { |article| article[:url] }
end

def ollama_chat(model, system_prompt, user_text)
  @client.chat(
    model:,
    messages: [
      { role: 'system', content: system_prompt },
      { role: 'user',   content: user_text }
    ],
    stream: false
  ).last.dig('message', 'content').to_s
end

def rewrite_with_qwen(title, description)
  # Qwen3 wraps its reasoning in <think>…</think> — strip before use
  ollama_chat(REWRITE_MODEL, REWRITE_SYSTEM_PROMPT, "Title: #{title}\n\n#{description}")
    .gsub(%r{<think>.*?</think>}m, '')
    .strip
end

def translate_with(text, prompt, model)
  result = ollama_chat(model, prompt, text)
  pp "translate_response: #{result}"
  result
end

def log_skip(reason, title)
  puts "Skipping #{reason}: #{title}"
  true
end

def skip_article?(article)
  title = article[:title].to_s
  url   = article[:url].to_s

  return log_skip('title prefix', title) if IGNORE_TITLE_PREFIXES.any? { |p| title.include?(p) }
  return log_skip('URL keyword', title)  if IGNORE_URL_KEYWORDS.any? { |k| url.include?(k) }
  return log_skip('already sent', title) if @db.get_first_value('SELECT 1 FROM articles WHERE url = ?', url)

  false
end

def rewrite_description(article)
  puts "Rewriting: #{article[:title]}"
  result = rewrite_with_qwen(article[:title], article[:description].to_s)
  result.empty? ? article[:description].to_s : result
rescue StandardError => e
  puts "Rewrite failed for '#{article[:title]}': #{e.message}"
  article[:description].to_s
end

def multi_mode?
  OLLAMA_MODELS.size > 1 || @prompts.size > 1
end

def build_message(article, translated_title, translated_description, prompt_index, model)
  text = "📢 *#{translated_title}*\n\n#{translated_description}\n\n\n" \
         "#{article[:url]}\n\nfollow @realbbcfarsi for more\n\n*#{article[:title]}*"
  text += "\n\n_Translation prompt: #{prompt_index + 1}, Model: #{model}_" if multi_mode?
  text
end

def save_article(article, translated_title, translated_description)
  sql = 'INSERT INTO articles ' \
        '(url, title, description, translated_title, translated_description, sent_at) ' \
        'VALUES (?, ?, ?, ?, ?, datetime("now"))'
  values = [ article[:url], article[:title], article[:description], translated_title, translated_description ]
  @db.execute(sql, values)
rescue StandardError
  nil
end

def post_to_telegram(article, title_fa, body_fa, prompt_index, model)
  @bot.api.send_message(
    chat_id: TELEGRAM_CHANNEL,
    text: build_message(article, title_fa, body_fa, prompt_index, model),
    parse_mode: 'Markdown'
  )
  save_article(article, title_fa, body_fa)
end

def translate_and_post(article, rewritten_description, prompt, prompt_index, model)
  title_fa = translate_with(article[:title], prompt, model)
  body_fa  = translate_with(rewritten_description, prompt, model)
  return puts("Empty translation for '#{article[:title]}'") if title_fa.empty? || body_fa.empty?

  post_to_telegram(article, title_fa, body_fa, prompt_index, model)
  puts "Posted: #{title_fa}"
rescue StandardError => e
  puts "Translation failed for '#{article[:title]}': #{e.message}"
  pp e.backtrace
end

def send_translations(article, rewritten_description)
  @prompts.each_with_index do |prompt, prompt_index|
    OLLAMA_MODELS.each do |model|
      translate_and_post(article, rewritten_description, prompt, prompt_index, model)
    end
  end
end

articles = fetch_bbc_articles(ACTIVE_FEEDS)
puts "Fetched #{articles.size} unique articles from BBC RSS feeds. Posting to #{TELEGRAM_CHANNEL}..."

articles.each do |article|
  next if skip_article?(article)

  rewritten_description = rewrite_description(article)
  send_translations(article, rewritten_description)
  sleep 5
end

puts 'Done posting news to Telegram!'
