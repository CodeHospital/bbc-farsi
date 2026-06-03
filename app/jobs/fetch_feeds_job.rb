class FetchFeedsJob < ApplicationJob
  queue_as :default

  def perform
    server, model = OllamaServer.pick(:rewrite)
    fetcher = BbcFeedFetcher.new

    Feed.enabled.each do |feed|
      fetcher.fetch(feed).each do |attrs|
        article = Article.find_or_initialize_by(url: attrs[:url])
        next if article.persisted?

        article.assign_attributes(attrs.merge(feed:))
        if article.save && server && model
          RewriteArticleJob.perform_later(article.id, server_id: server.id, model:)
        end
      end
    end
  end
end
