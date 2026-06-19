# Periodic, Ollama-free work that used to run on the Solid Queue cron schedule.
# Now driven by an external scheduler (e.g. system cron) calling these tasks.
#
#   bin/rails bbc:fetch          # pull enabled RSS feeds, enqueue rewrite tasks
#   bin/rails bbc:autopost       # post active translations to autopost channels
#   bin/rails bbc:reclaim_stale  # return timed-out claimed tasks to the queue
#
# Example crontab:
#   */30 * * * *  cd /path/to/app && bin/rails bbc:fetch         >> log/cron.log 2>&1
#   */5  * * * *  cd /path/to/app && bin/rails bbc:autopost      >> log/cron.log 2>&1
#   */10 * * * *  cd /path/to/app && bin/rails bbc:reclaim_stale >> log/cron.log 2>&1
namespace :bbc do
  desc "Fetch enabled RSS feeds and enqueue a rewrite task per new article"
  task fetch: :environment do
    count = FeedIngestor.run
    puts "Ingested #{count} new article(s)."
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
