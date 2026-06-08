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
end
