module ApplicationHelper
  COUNTRY_NAMES = {
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

  # Convert a country into a flag emoji. Accepts either a 2-letter ISO code
  # (e.g. "US" → 🇺🇸) or a full country name (e.g. "United States" → 🇺🇸),
  # falling back to 🌐 when the country can't be resolved.
  def country_flag(country)
    code = country.to_s.strip
    code = code_for_country_name(code) if code.length != 2

    if code.to_s.length == 2
      code.upcase.chars.map { |c| (c.ord - 65 + 0x1F1E6).chr(Encoding::UTF_8) }.join
    else
      "🌐"
    end
  end

  # Reverse lookup: full country name → 2-letter ISO code (case-insensitive),
  # or nil when unknown.
  def code_for_country_name(name)
    @country_codes_by_name ||=
      COUNTRY_NAMES.each_with_object({}) { |(code, country), map| map[country.downcase] = code }
    @country_codes_by_name[name.to_s.strip.downcase]
  end

  # Human-readable country name for a 2-letter ISO code, or the code itself.
  def country_name(code) = COUNTRY_NAMES[code.to_s.upcase] || code.to_s

  # Generic sortable column header link.
  # Preserves all current query params, toggles direction for the active column,
  # and resets pagination. Uses ▲/▼ to indicate the active sort direction.
  def sort_link(column, label)
    current_sort = params[:sort].to_s
    current_dir  = params[:dir] == "asc" ? "asc" : "desc"
    active       = current_sort == column
    next_dir     = active && current_dir == "asc" ? "desc" : "asc"
    indicator    = active ? (current_dir == "asc" ? " ▲" : " ▼") : ""
    target       = url_for(request.query_parameters.merge("sort" => column, "dir" => next_dir).except("page"))
    link_to "#{label}#{indicator}", target, class: "text-reset text-decoration-none"
  end
end
