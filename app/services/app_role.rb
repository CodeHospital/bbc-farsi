# Which slice of the monolith this process serves, from the APP_ROLE boot knob
# (ENV, like RAILS_ENV/PORT — not a credential). The same image runs as several
# docker-compose services (see docker-compose.yml), each with its own role:
#
#   all     (default) everything — development, tests, single-container deploys
#   public  the news portal + guest edit links          (khabarestan.com)
#   admin   the admin UI + ActionCable                  (admin.khabarestan.com)
#   api     worker task queue + webhooks                (api.khabarestan.com)
#   worker  no web traffic; runs the background pollers (bin/rails pollers:run)
#
# Routes for every section are drawn in every role (so URL helpers work across
# hosts) but only *match* in a process whose role serves that section — see
# AppHosts.serves_request? and config/routes.rb.
module AppRole
  module_function

  ROLES = %w[all public admin api worker].freeze

  def current
    role = ENV.fetch("APP_ROLE", "all").to_s.strip.downcase.presence || "all"
    ROLES.include?(role) ? role : raise(ArgumentError, "Unknown APP_ROLE #{role.inspect} (expected one of #{ROLES.join(', ')})")
  end

  def all?    = current == "all"
  def worker? = current == "worker"

  # section: :public, :admin or :api.
  def serves?(section) = all? || current == section.to_s

  # Lets the public container keep answering /api/* on the public host while
  # the worker, llmarkt callbacks and the Telegram webhook are moved over to
  # api.khabarestan.com. Turn off once nothing calls the old URLs any more.
  def legacy_api_on_public_host? = ActiveModel::Type::Boolean.new.cast(ENV["LEGACY_API_ON_PUBLIC"]) || false

  # In-process pollers (BackgroundPollers) run inside `bin/rails server` only
  # for the all-in-one role; split deployments run them in the dedicated
  # worker service instead so web containers stay stateless.
  def web_server_runs_pollers? = all?
end
