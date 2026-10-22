namespace :pollers do
  desc "Run the background pollers (feed fetch, Telegram autopost, article images) in the foreground — the APP_ROLE=worker service"
  task run: :environment do
    $stdout.sync = true
    Rails.logger.info "BackgroundPollers: starting #{BackgroundPollers::POLLERS.map(&:name).join(', ')}"
    BackgroundPollers.start_all.each(&:join)
  end
end
