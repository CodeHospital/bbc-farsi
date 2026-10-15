# Periodic, Ollama-free work that used to run on the Solid Queue cron schedule.
# Now driven by an external scheduler (e.g. system cron) calling these tasks.
#
#   bin/rails bbc:fetch            # pull every enabled RSS feed now
#   bin/rails bbc:fetch_scheduled  # pull only feeds scheduled for this hour
#   bin/rails bbc:autopost         # post active translations to autopost channels
#   bin/rails bbc:reclaim_stale    # return timed-out claimed tasks to the queue
#
# Example crontab:
#   0    * * * *  cd /path/to/app && bin/rails bbc:fetch_scheduled >> log/cron.log 2>&1
#   */5  * * * *  cd /path/to/app && bin/rails bbc:autopost        >> log/cron.log 2>&1
#   */10 * * * *  cd /path/to/app && bin/rails bbc:reclaim_stale   >> log/cron.log 2>&1
namespace :bbc do
  desc "Fetch enabled RSS feeds and enqueue a rewrite task per new article"
  task fetch: :environment do
    count = FeedIngestor.run
    puts "Ingested #{count} new article(s)."
  end

  desc "Fetch only the enabled feeds scheduled for the current hour (run hourly from cron)"
  task fetch_scheduled: :environment do
    result = FeedIngestor.run_scheduled
    puts "Fetched #{result[:feed_count]} scheduled feed(s), ingested #{result[:new_count]} new article(s)."
  end

  desc "Post active, completed translations to autopost channels"
  task autopost: :environment do
    count = Autoposter.run_all
    puts "Posted #{count} translation(s)."
  end

  desc "Return claimed tasks that have been stuck longer than Task::STALE_AFTER to pending"
  task reclaim_stale: :environment do
    count = Task.reclaim_stale!
    puts "Reclaimed #{count} stale task(s)."
  end

  desc "Enqueue an AI task to pick the homepage featured stories"
  task feature: :environment do
    candidates = FeaturedSelector.candidates
    if candidates.empty?
      puts "No translated stories to feature."
      next
    end

    server, model = OllamaServer.pick(:refine)
    server, model = OllamaServer.pick(:translate) unless server
    abort "No Ollama servers with refine/translate models configured." unless server

    Task.enqueue_feature(candidates, server:, model:)
    puts "Enqueued feature task (#{server.name} / #{model}) over #{candidates.size} candidate(s)."
  end

  desc "Backfill slug columns for existing translations and articles (run once after the slug migration)"
  task backfill_slugs: :environment do
    unless Translation.column_names.include?("slug")
      abort "slug column not found — run bin/rails db:migrate first."
    end
    translation_count = 0
    Translation.where(slug: nil).find_each do |translation|
      translation.save!
      translation_count += 1
      print "."
    end
    article_count = 0
    Article.where(slug: nil).find_each do |article|
      article.save!
      article_count += 1
      print "."
    end
    puts "\nBackfilled #{translation_count} translation(s) and #{article_count} article(s)."
  end

  desc "List which app credentials are set or missing (names only — values are never printed)"
  task credentials: :environment do
    required = %i[admin_username admin_password admin_email worker_api_token]
    required << :database_url if Rails.env.production?
    optional = %i[app_base_url llmarkt_api_url llmarkt_api_key llmarkt_model_match resend_api_key sender_email
                  sentry_dsn telegram_admin_bot_token telegram_admin_chat_id telegram_admin_webhook_secret ollama_url]

    missing_required = required.reject { |key| AppCredentials.fetch(key).present? }
    { "required" => required, "optional" => optional }.each do |group, keys|
      keys.each { |key| puts format("  %-8s %-30s %s", group, key, AppCredentials.fetch(key).present? ? "set" : "MISSING") }
    end
    abort "Missing required credentials: #{missing_required.join(', ')} — run bin/rails credentials:edit" if missing_required.any?
  end

  desc "Enqueue AI bias/fact analysis tasks for non-archived articles that have no analysis yet (backfill)"
  task analyze: :environment do
    candidates = ArticleAnalyzer.unanalyzed_candidates
    if candidates.none?
      puts "No unanalyzed articles."
      next
    end

    server, model = OllamaServer.pick(:rewrite)
    abort "No Ollama servers with rewrite models configured." unless server

    enqueued_count = 0
    candidates.find_each do |article|
      Task.enqueue_analyze(article, server:, model:)
      enqueued_count += 1
    end
    puts "Enqueued #{enqueued_count} analyze task(s) (#{server.name} / #{model})."
  end

  desc "Enqueue AI tag-generation tasks for translated articles that have no tags yet"
  task tag: :environment do
    candidates = TagGenerator.untagged_candidates
    if candidates.empty?
      puts "No untagged translated articles."
      next
    end

    server, model = OllamaServer.pick(:refine)
    server, model = OllamaServer.pick(:translate) unless server
    abort "No Ollama servers with refine/translate models configured." unless server

    candidates.each { |translation| Task.enqueue_tag(translation, server:, model:) }
    puts "Enqueued #{candidates.size} tag task(s) (#{server.name} / #{model})."
  end
end
