# Fetches all enabled RSS feeds, upserts new articles, and creates a rewrite
# Task for each new article. Replaces the old FetchFeedsJob.
#
# Runs synchronously — invoked from the admin "Fetch now" button and from the
# `bbc:fetch` rake task (which an external scheduler/cron can call). RSS fetching
# needs no Ollama access, so it stays inside the Rails app.
class FeedIngestor
  FETCHER_CLASSES = {
    "bbc"       => BbcFeedFetcher,
    "nyt"       => NytFeedFetcher,
    "adhocnews" => AdhocnewsFeedFetcher
  }.freeze

  # Attributes an existing Article is refreshed from when its feed entry
  # changed (e.g. BBC/NYT edited a headline after publishing).
  UPDATABLE_ATTRS = %i[title description published_at].freeze

  # Returns the number of new articles ingested.
  def self.run
    server, model = OllamaServer.pick(:rewrite)
    fetchers = Hash.new { |cache, source| cache[source] = fetcher_for(source) }
    new_count = 0

    Feed.enabled.each { |feed| new_count += ingest_feed(feed, fetchers[feed.source], server, model) }

    new_count
  end

  # Fetches only the enabled feeds scheduled for the current hour (see
  # Feed#fetch_hour, server-local). Called every hour by `bbc:fetch_scheduled`
  # and by the in-process poller in config/initializers/feed_fetch_scheduler.rb.
  #
  # Each feed is claimed with a conditional UPDATE before being fetched, so a
  # feed is fetched at most once per hour slot even when both run, or when the
  # sweep is called more often than hourly.
  #
  # Returns { feed_count:, new_count: }.
  def self.run_scheduled(now = Time.now)
    hour_start    = now.change(min: 0, sec: 0)
    server, model = OllamaServer.pick(:rewrite)
    fetchers      = Hash.new { |cache, source| cache[source] = fetcher_for(source) }
    feed_count    = 0
    new_count     = 0

    Feed.enabled.where(fetch_hour: now.hour).each do |feed|
      next unless claim_scheduled_fetch(feed, hour_start, now)

      feed_count += 1
      new_count  += ingest_feed(feed, fetchers[feed.source], server, model)
    end

    { feed_count:, new_count: }
  end

  # True when this process won the race to fetch the feed for the current hour.
  # Stamps the sweep's own clock rather than Time.current so the marker always
  # falls inside the slot it claims.
  def self.claim_scheduled_fetch(feed, hour_start, now)
    Feed.where(id: feed.id)
        .where("last_scheduled_fetch_at IS NULL OR last_scheduled_fetch_at < ?", hour_start)
        .update_all(last_scheduled_fetch_at: now) == 1
  end

  # Upserts one feed's entries, enqueuing a rewrite task per new article.
  # Returns the number of new articles.
  def self.ingest_feed(feed, fetcher, server, model)
    new_count = 0

    fetcher.fetch(feed).each do |attrs|
      article = Article.find_or_initialize_by(url: attrs[:url])
      next if article.persisted?

      article.assign_attributes(attrs.merge(feed:))
      next unless article.save

      new_count += 1
      Task.enqueue_rewrite(article, server:, model:) if server && model
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
