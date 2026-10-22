# Starts the periodic poll loops (feed fetch, Telegram autopost, article
# images) when this process boots as an actual all-in-one web server. Split
# deployments (APP_ROLE=public/admin/api) leave them to the worker service
# instead — see BackgroundPollers and AppRole.
#
# Only under `bin/rails server` (`Rails::Server` is defined there), so a
# one-off `bin/rails runner` script or the test suite never spawns a thread.
if defined?(Rails::Server) && !Rails.env.test?
  Rails.application.config.after_initialize do
    BackgroundPollers.start_all if AppRole.web_server_runs_pollers?
  end
end
