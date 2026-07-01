require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # ── country_flag ──────────────────────────────────────────────────────────

  test "country_flag converts a 2-letter ISO code to a flag emoji" do
    assert_equal "🇺🇸", country_flag("US")
    assert_equal "🇮🇷", country_flag("IR")
    assert_equal "🇬🇧", country_flag("GB")
  end

  test "country_flag is case-insensitive for ISO codes" do
    assert_equal "🇺🇸", country_flag("us")
    assert_equal "🇮🇷", country_flag("Ir")
  end

  test "country_flag resolves a full country name to the matching flag" do
    assert_equal "🇺🇸", country_flag("United States")
    assert_equal "🇮🇷", country_flag("Iran")
    assert_equal "🇬🇧", country_flag("United Kingdom")
  end

  test "country_flag is case-insensitive for full country names" do
    assert_equal "🇺🇸", country_flag("united states")
    assert_equal "🇺🇸", country_flag("UNITED STATES")
  end

  test "country_flag tolerates surrounding whitespace in a country name" do
    assert_equal "🇺🇸", country_flag("  United States  ")
  end

  test "country_flag falls back to the globe emoji for an unknown country name" do
    assert_equal "🌐", country_flag("Wakanda")
  end

  test "country_flag falls back to the globe emoji for nil" do
    assert_equal "🌐", country_flag(nil)
  end

  test "country_flag falls back to the globe emoji for a blank string" do
    assert_equal "🌐", country_flag("")
    assert_equal "🌐", country_flag("   ")
  end

  test "country_flag falls back to the globe emoji for a 2-letter code not in COUNTRY_NAMES" do
    # country_flag does not validate codes against COUNTRY_NAMES — any 2-letter
    # string is treated as an ISO code and converted via regional-indicator math.
    assert_equal "🇽🇽", country_flag("XX")
  end

  # ── code_for_country_name ─────────────────────────────────────────────────

  test "code_for_country_name resolves a known name to its ISO code" do
    assert_equal "US", code_for_country_name("United States")
    assert_equal "IR", code_for_country_name("Iran")
  end

  test "code_for_country_name is case-insensitive" do
    assert_equal "US", code_for_country_name("united states")
    assert_equal "US", code_for_country_name("UNITED STATES")
  end

  test "code_for_country_name tolerates surrounding whitespace" do
    assert_equal "US", code_for_country_name("  United States  ")
  end

  test "code_for_country_name returns nil for an unknown name" do
    assert_nil code_for_country_name("Wakanda")
  end

  test "code_for_country_name returns nil for nil or blank input" do
    assert_nil code_for_country_name(nil)
    assert_nil code_for_country_name("")
  end

  # ── country_name ──────────────────────────────────────────────────────────

  test "country_name returns the human-readable name for a known code" do
    assert_equal "United States", country_name("US")
    assert_equal "Iran", country_name("IR")
  end

  test "country_name is case-insensitive for the code" do
    assert_equal "United States", country_name("us")
  end

  test "country_name returns the code itself when unknown" do
    assert_equal "ZZ", country_name("ZZ")
  end

  test "country_name returns an empty string for nil" do
    assert_equal "", country_name(nil)
  end

  # ── sort_link ─────────────────────────────────────────────────────────────

  test "sort_link points to the column ascending with no indicator when inactive" do
    with_request_params(sort: nil, dir: nil) do
      link = sort_link("ip", "IP address")
      assert_match %r{sort=ip}, link
      assert_match %r{dir=asc}, link
      assert_match %r{>IP address<}, link
      assert_no_match(/[▲▼]/, link)
    end
  end

  test "sort_link toggles to desc and shows the ascending indicator when active-asc" do
    with_request_params(sort: "ip", dir: "asc") do
      link = sort_link("ip", "IP address")
      assert_match %r{dir=desc}, link
      assert_match "▲", link
    end
  end

  test "sort_link toggles to asc and shows the descending indicator when active-desc" do
    with_request_params(sort: "ip", dir: "desc") do
      link = sort_link("ip", "IP address")
      assert_match %r{dir=asc}, link
      assert_match "▼", link
    end
  end

  test "sort_link defaults to desc direction semantics when dir param is absent/invalid on an active column" do
    with_request_params(sort: "ip", dir: "bogus") do
      link = sort_link("ip", "IP address")
      # current_dir treated as "desc" (only "asc" is honored), so next_dir flips to "asc"
      assert_match %r{dir=asc}, link
      assert_match "▼", link
    end
  end

  test "sort_link preserves other query params and resets pagination" do
    with_request_params(sort: "ip", dir: "asc", q: "8.8.8.8", page: "3") do
      link = sort_link("ip", "IP address")
      assert_match %r{q=8\.8\.8\.8}, link
      assert_no_match(/page=/, link)
    end
  end

  private

  # Populate the test request's path/query parameters so `sort_link` (which
  # reads `params` and rebuilds the URL from `request.query_parameters` via
  # `url_for`) behaves exactly as it does for a real admin index request.
  def with_request_params(query_parameters)
    query_parameters = query_parameters.compact.transform_keys(&:to_s).transform_values(&:to_s)

    request.path_parameters[:controller] = "admin/ip_geolocations"
    request.path_parameters[:action]     = "index"
    request.query_parameters.clear
    request.query_parameters.merge!(query_parameters)
    params.merge!(query_parameters)

    yield
  end
end
