# Fetches all enabled RSS feeds, upserts new articles, and creates a rewrite
# Task for each new article. Replaces the old FetchFeedsJob.
#
# Runs synchronously — invoked from the admin "Fetch now" button and from the
# `bbc:fetch` rake task (which an external scheduler/cron can call). RSS fetching
# needs no Ollama access, so it stays inside the Rails app.
class FeedIngestor
  # Returns the number of new articles ingested.
  def self.run
    server, model = OllamaServer.pick(:rewrite)
    fetcher = BbcFeedFetcher.new
    new_count = 0

    Feed.enabled.each do |feed|
      fetcher.fetch(feed).each do |attrs|
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
end
