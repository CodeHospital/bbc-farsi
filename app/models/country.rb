# ISO 3166-1 alpha-2 country code <-> name lookup. Shared by the admin UI
# (ApplicationHelper#country_flag/#country_name) and ArticleView/IpGeolocation,
# which derive a country_code from the country name returned by the
# geolocation service.
module Country
  NAMES = {
    "AF" => "Afghanistan", "AR" => "Argentina", "AU" => "Australia",
    "AT" => "Austria",     "BE" => "Belgium",    "BR" => "Brazil",
    "CA" => "Canada",      "CN" => "China",       "CO" => "Colombia",
    "DK" => "Denmark",     "EG" => "Egypt",       "FI" => "Finland",
    "FR" => "France",      "DE" => "Germany",     "GH" => "Ghana",
    "GR" => "Greece",      "HK" => "Hong Kong",   "IN" => "India",
    "ID" => "Indonesia",   "IQ" => "Iraq",        "IR" => "Iran",
    "IE" => "Ireland",     "IL" => "Palestine",      "IT" => "Italy",
    "JP" => "Japan",       "JO" => "Jordan",      "KZ" => "Kazakhstan",
    "KE" => "Kenya",       "KW" => "Kuwait",      "LB" => "Lebanon",
    "MY" => "Malaysia",    "MX" => "Mexico",      "MA" => "Morocco",
    "NL" => "Netherlands", "NZ" => "New Zealand", "NG" => "Nigeria",
    "NO" => "Norway",      "OM" => "Oman",        "PK" => "Pakistan",
    "PL" => "Poland",      "PT" => "Portugal",    "QA" => "Qatar",
    "RU" => "Russia",      "SA" => "Saudi Arabia", "ZA" => "South Africa",
    "KR" => "South Korea", "ES" => "Spain",       "SE" => "Sweden",
    "CH" => "Switzerland", "SY" => "Syria",       "TW" => "Taiwan",
    "TR" => "Turkey",      "UA" => "Ukraine",     "AE" => "UAE",
    "GB" => "United Kingdom", "US" => "United States", "UZ" => "Uzbekistan",
    "VN" => "Vietnam",     "YE" => "Yemen"
  }.freeze

  CODES_BY_NAME = NAMES.each_with_object({}) { |(code, name), map| map[name.downcase] = code }.freeze

  # 2-letter ISO code -> human-readable name, or the code itself when unknown.
  def self.name_for(code) = NAMES[code.to_s.upcase] || code.to_s

  # Full country name (case/whitespace-insensitive) -> 2-letter ISO code, or nil when unknown.
  def self.code_for_name(name) = CODES_BY_NAME[name.to_s.strip.downcase]
end
