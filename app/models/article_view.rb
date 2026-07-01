require "net/http"
require "json"

class ArticleView < ApplicationRecord
  belongs_to :article

  CF_COUNTRY_HEADER   = "HTTP_CF_IPCOUNTRY"
  CF_FRONT_HEADER     = "HTTP_CLOUDFRONT_VIEWER_COUNTRY"
  GENERIC_COUNTRY_HDR = "HTTP_X_COUNTRY_CODE"
  LOCAL_IPS           = %w[127.0.0.1 ::1 localhost].freeze

  GEO_URL     = Rails.application.credentials.dig(:geo_url)
  GEO_TIMEOUT = { open: 2, read: 3 }.freeze

  # Read at call-time so the value can be rotated without a restart.
  # Set GEO_SECRET in .env (or server env) to override the default.
  def self.geo_secret = Rails.application.credentials.dig(:geo_secret)

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
  end

  private_class_method def self.extract_location(request)
    ip = request.remote_ip.to_s.strip
    return [ nil, nil ] if ip.blank? || LOCAL_IPS.include?(ip)

    geolocate_ip(ip)
  rescue => error
    Rails.logger.warn("[ArticleView] extract_location failed: #{error.message}")
    [ nil, nil ]
  end

  # Resolve an IP to a [country_name, city_name] pair, using a local cache so a
  # given IP is only ever fetched from the geolocation service once. Cache hits
  # (including ones that resolved to no location) skip the HTTP call entirely.
  private_class_method def self.geolocate_ip(ip)
    cached = IpGeolocation.find_by(ip: ip)
    if cached
      cached.record_hit!
      return [ cached.country_name.presence, cached.city_name.presence ]
    end

    country, city = fetch_country_from_service(ip)
    IpGeolocation.create!(ip: ip, country_name: country, city_name: city, lookups_count: 1, last_used_at: Time.current)
    [ country.presence, city.presence ]
  rescue ActiveRecord::RecordNotUnique
    # Another request cached this IP first — just read it back.
    cached = IpGeolocation.find_by(ip: ip)
    [ cached&.country_name.presence, cached&.city_name.presence ]
  rescue => error
    Rails.logger.warn("[ArticleView] geolocate_ip(#{ip}) failed: #{error.message}")
    [ nil, nil ]
  end

  # Perform the actual HTTP lookup. Raises on any transport/parse error so the
  # caller can avoid caching a spurious "no country" result for a failed call.
  private_class_method def self.fetch_country_from_service(ip)
    uri = URI(GEO_URL+ip)
    # uri.query = URI.encode_www_form(secret: geo_secret, action: "get_location", ip: ip)

    response = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: GEO_TIMEOUT[:open],
                               read_timeout: GEO_TIMEOUT[:read]) do |http|
      http.get(uri.request_uri)
    end

    data = JSON.parse(response.body)
    country = data.dig("data", "country").to_s.strip
    city = data.dig("data", "city").to_s.strip
    return country, city
  end
end
