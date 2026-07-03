# Fetches all enabled RSS feeds, upserts new articles, and creates a rewrite
# Task for each new article. Replaces the old FetchFeedsJob.
#
# Runs synchronously — invoked from the admin "Fetch now" button and from the
# `bbc:fetch` rake task (which an external scheduler/cron can call). RSS fetching
# needs no Ollama access, so it stays inside the Rails app.
class FeedIngestor
  FETCHER_CLASSES = {
    "bbc" => BbcFeedFetcher,
    "nyt" => NytFeedFetcher
  }.freeze

  # Attributes an existing Article is refreshed from when its feed entry
  # changed (e.g. BBC/NYT edited a headline after publishing).
  UPDATABLE_ATTRS = %i[title description published_at].freeze

  # Returns the number of new articles ingested.
  def self.run
    server, model = OllamaServer.pick(:rewrite)
    fetchers = Hash.new { |cache, source| cache[source] = fetcher_for(source) }
    new_count = 0

    Feed.enabled.each do |feed|
      fetchers[feed.source].fetch(feed).each do |attrs|
        article = Article.find_or_initialize_by(url: attrs[:url])
        next if article.persisted?

        article.assign_attributes(attrs.merge(feed:))
        next unless article.save

        new_count += 1
        Task.enqueue_rewrite(article, server:, model:) if server && model
      end
    end

    new_count
  end

  # Fetches a single feed and reports what happened to every entry: how many
  # articles were newly created, how many existing ones were refreshed, and
  # why every other entry was skipped. Used by the admin per-feed Fetch button.
  def self.run_one(feed)
    result = fetcher_for(feed.source).fetch_with_report(feed)
    return { new_count: 0, updated_count: 0, skipped: [], error: result[:error] } if result[:error]

    server, model = OllamaServer.pick(:rewrite)
    new_count     = 0
    updated_count = 0
    skipped       = result[:ignored].dup

    result[:entries].each do |attrs|
      article = Article.find_or_initialize_by(url: attrs[:url])

      if article.new_record?
        article.assign_attributes(attrs.merge(feed:))
        if article.save
          new_count += 1
          Task.enqueue_rewrite(article, server:, model:) if server && model
        else
          skipped << { title: attrs[:title], url: attrs[:url], reason: article.errors.full_messages.to_sentence }
        end
      else
        article.assign_attributes(attrs.slice(*UPDATABLE_ATTRS))
        if !article.changed?
          skipped << { title: attrs[:title], url: attrs[:url], reason: "already up to date" }
        elsif article.save
          updated_count += 1
        else
          skipped << { title: attrs[:title], url: attrs[:url], reason: article.errors.full_messages.to_sentence }
        end
      end
    end

    { new_count:, updated_count:, skipped:, error: nil }
  end

  def self.fetcher_for(source)
    FETCHER_CLASSES.fetch(source, BbcFeedFetcher).new
  end
end
