require "net/http"
require "json"

class ArticleView < ApplicationRecord
  belongs_to :article

  LOCAL_IPS = %w[127.0.0.1 ::1 localhost].freeze

  # Record a page-view event. Silently swallows errors so a missing migration
  # or DB hiccup never surfaces to the reader.
  def self.track!(article:, translation: nil, edition: "fa", request:)
    country_name, city_name = extract_location(request)
    create!(
      article_id:     article.id,
      translation_id: translation.is_a?(Translation) ? translation.id : nil,
      country_name:   country_name,
      city_name:      city_name,
      country_code:   Country.code_for_name(country_name),
      edition:        edition
    )
  rescue => error
    Rails.logger.warn("[ArticleView] tracking failed: #{error.message}")
    Sentry.capture_exception(error)
  end

  private_class_method def self.extract_location(request)
    location_for_ip(request.remote_ip)
  end

  # [country_name, city_name] for an IP, or [nil, nil] for blank/local IPs and
  # on any lookup failure. Shares the IpGeolocation cache with page views.
  def self.location_for_ip(ip)
    ip = ip.to_s.strip
    # Without a configured endpoint no lookup is attempted, and nothing is cached.
    return [ nil, nil ] if ip.blank? || LOCAL_IPS.include?(ip) || AppCredentials.ip_location_api_url.blank?

    geolocate_ip(ip)
  rescue => error
    Rails.logger.warn("[ArticleView] location_for_ip failed: #{error.message}")
    Sentry.capture_exception(error)
    [ nil, nil ]
  end

  # Resolve an IP to a [country_name, city_name] pair, using a local cache so a
  # given IP is only ever fetched from the geolocation service once. Cache hits
  # (including ones that resolved to no location) skip the HTTP call entirely.
  private_class_method def self.geolocate_ip(ip)
    cached = IpGeolocation.find_by(ip: ip)
    if cached
      cached.record_hit!
      SentryBreadcrumb.record("ArticleView.geolocate_ip", category: "geolocation",
        data: { source: "cache", country_name: cached.country_name, city_name: cached.city_name })
      return [ cached.country_name.presence, cached.city_name.presence ]
    end

    country, city = fetch_country_from_service(ip)
    IpGeolocation.create!(ip: ip, country_name: country, city_name: city, lookups_count: 1, last_used_at: Time.current)
    SentryBreadcrumb.record("ArticleView.geolocate_ip", category: "geolocation",
      data: { source: "service", country_name: country, city_name: city })
    [ country.presence, city.presence ]
  rescue ActiveRecord::RecordNotUnique => error
    # Another request cached this IP first — just read it back.
    Sentry.capture_exception(error)
    cached = IpGeolocation.find_by(ip: ip)
    SentryBreadcrumb.record("ArticleView.geolocate_ip", category: "geolocation",
      data: { source: "concurrent_cache", country_name: cached&.country_name, city_name: cached&.city_name })
    [ cached&.country_name.presence, cached&.city_name.presence ]
  rescue => error
    Rails.logger.warn("[ArticleView] geolocate_ip(#{ip}) failed: #{error.message}")
    Sentry.capture_exception(error)
    SentryBreadcrumb.record("ArticleView.geolocate_ip failed", category: "geolocation",
      level: "warning", data: { error_class: error.class.name, error_message: error.message.truncate(300) })
    [ nil, nil ]
  end

  # Perform the actual HTTP lookup against the location endpoint configured in
  # credentials (ip_location_api_url). Response shape:
  #   { "success": true, "data": { "city": "...", "country": "..." } }
  # Raises on any transport/parse error so the caller can avoid caching a
  # spurious "no country" result for a failed call.
  private_class_method def self.fetch_country_from_service(ip)
    uri = URI.parse(AppCredentials.ip_location_api_url)
    uri.query = URI.encode_www_form(ip: ip)
    # Short timeouts: this can run inside a visitor's request (page view, guest edit).
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 3) do |http|
      http.get(uri.request_uri).body
    end
    location_response = JSON.parse(response)
    return [ nil, nil ] unless location_response["success"]

    location_data = location_response["data"] || {}
    [ location_data["country"], location_data["city"] ]
  end
end
