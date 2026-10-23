# The public, admin and API hostnames, from credentials:
#
#   app_base_url    https://www.khabarestan.com     public portal (also mail domain)
#   admin_base_url  https://admin.khabarestan.com   admin UI — setting it turns the split on
#   api_base_url    https://api.khabarestan.com     worker API + webhooks (optional)
#   worker_base_url https://worker.khabarestan.com  poller status page (optional)
#
# With admin_base_url unset (development, tests, single-host deploys) nothing
# changes: admin stays under /admin on the one host. With it set, the admin UI
# moves to the admin host without the /admin prefix, /admin/* on the public host
# 301-redirects there, and each section only answers on its own host.
module AppHosts
  module_function

  def public_base_url = Llmarkt.app_base_url
  def admin_base_url  = base_url(:admin_base_url)

  # Where llmarkt callbacks and the Telegram webhook are registered. Falls back
  # to the public URL, where /api/* lives when there is no API host.
  def api_base_url = configured_api_base_url || public_base_url

  # api_base_url exactly as configured: nil means "no separate API host".
  def configured_api_base_url = base_url(:api_base_url)

  # nil means the status page stays at /worker on the public host.
  def worker_base_url = base_url(:worker_base_url)

  def public_host = host_of(public_base_url)
  def admin_host  = host_of(admin_base_url)
  def api_host    = host_of(configured_api_base_url)
  def worker_host = host_of(worker_base_url)

  # The www / bare-domain twin of the public host (www.khabarestan.com ↔
  # khabarestan.com), which 301-redirects to the canonical public URL.
  def public_host_alias
    return if public_host.blank?

    public_host.start_with?("www.") ? public_host.delete_prefix("www.") : "www.#{public_host}"
  end

  def public_host_alias_request?(request) = split? && public_host_alias.present? && request.host == public_host_alias

  def canonical_public_url(request) = "#{public_base_url}#{request.fullpath}"

  # Never in development: credentials are shared across environments, and a
  # local server answers on localhost, not on the production domains.
  def split? = admin_host.present? && !Rails.env.development?

  # Which section a request's Host header belongs to in a split deployment.
  # Anything that isn't the admin, API or worker host (apex, www, …) is public.
  def section_for(request)
    case request.host
    when admin_host  then :admin
    when api_host    then :api
    when worker_host then :worker
    else :public
    end
  end

  # Route constraint: does this process, for this request's host, serve the
  # given section's routes?
  def serves_request?(section, request)
    return AppRole.serves?(section) unless split?

    request_section = section_for(request)
    return true if request_section == section && AppRole.serves?(section)

    return false unless request_section == :public && AppRole.serves?(:public)

    case section
    # /api/* on the public host: when there is no API host, or during the
    # LEGACY_API_ON_PUBLIC transition.
    when :api    then api_host.blank? || AppRole.legacy_api_on_public_host?
    # /worker on the public host when there is no worker host.
    when :worker then worker_host.blank?
    else false
    end
  end

  def constraint_for(section) = ->(request) { serves_request?(section, request) }

  # The API landing page owns "/" on the API host, so it must never match "/"
  # on another host (the public portal's root!): with a separate API host it
  # needs the request to be on it; otherwise it lives at /api.
  def api_landing_constraint
    lambda do |request|
      if split? && api_host.present?
        section_for(request) == :api && AppRole.serves?(:api)
      else
        serves_request?(:api, request)
      end
    end
  end

  def api_landing_at_root? = split? && api_host.present?

  # Extra url_for options so admin pages link to the portal on the public host
  # (news_url(..., **AppHosts.public_url_options)). Empty when not split, so
  # the links stay on the current host.
  def public_url_options = url_options_for(public_base_url)

  # Same for links into the admin UI from other hosts (the worker status page).
  def admin_url_options = url_options_for(admin_base_url)

  # Target for the /admin/* → admin host redirect.
  def admin_redirect_url(admin_path, query_string)
    url = "#{admin_base_url}/#{admin_path}"
    query_string.present? ? "#{url}?#{query_string}" : url
  end

  def url_options_for(target_base_url)
    return {} unless split? && target_base_url.present?

    uri = URI.parse(target_base_url)
    { host: uri.host, port: uri.port, protocol: uri.scheme }
  end

  def base_url(key) = AppCredentials.fetch(key).to_s.chomp("/").presence

  def host_of(url) = (URI.parse(url).host if url.present?)
end
