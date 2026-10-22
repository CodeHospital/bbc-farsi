# The public, admin and API hostnames, from credentials:
#
#   app_base_url    https://khabarestan.com        public portal (also mail domain)
#   admin_base_url  https://admin.khabarestan.com  admin UI — setting it turns the split on
#   api_base_url    https://api.khabarestan.com    worker API + webhooks (optional)
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

  def public_host = host_of(public_base_url)
  def admin_host  = host_of(admin_base_url)
  def api_host    = host_of(configured_api_base_url)

  def split? = admin_host.present?

  # Which section a request's Host header belongs to in a split deployment.
  # Anything that isn't the admin or API host (apex, www, …) is public.
  def section_for(request)
    case request.host
    when admin_host then :admin
    when api_host   then :api
    else :public
    end
  end

  # Route constraint: does this process, for this request's host, serve the
  # given section's routes?
  def serves_request?(section, request)
    return AppRole.serves?(section) unless split?

    request_section = section_for(request)
    return true if request_section == section && AppRole.serves?(section)

    # /api/* on the public host: when there is no API host, or during the
    # LEGACY_API_ON_PUBLIC transition.
    section == :api && request_section == :public && AppRole.serves?(:public) &&
      (api_host.blank? || AppRole.legacy_api_on_public_host?)
  end

  def constraint_for(section) = ->(request) { serves_request?(section, request) }

  # Extra url_for options so admin pages link to the portal on the public host
  # (news_url(..., **AppHosts.public_url_options)). Empty when not split, so
  # the links stay on the current host.
  def public_url_options
    return {} unless split? && public_base_url.present?

    uri = URI.parse(public_base_url)
    { host: uri.host, port: uri.port, protocol: uri.scheme }
  end

  # Target for the /admin/* → admin host redirect.
  def admin_redirect_url(admin_path, query_string)
    url = "#{admin_base_url}/#{admin_path}"
    query_string.present? ? "#{url}?#{query_string}" : url
  end

  def base_url(key) = AppCredentials.fetch(key).to_s.chomp("/").presence

  def host_of(url) = (URI.parse(url).host if url.present?)
end
