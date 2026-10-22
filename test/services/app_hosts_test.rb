require "test_helper"

class AppHostsTest < ActiveSupport::TestCase
  teardown do
    ENV.delete("APP_ROLE")
    restore_llmarkt_config
  end

  # Only AppHosts' own host logic is under test here, not route drawing.
  def stub_hosts_without_redrawing(admin_base_url:, api_base_url: nil)
    AppHosts.define_singleton_method(:admin_base_url) { admin_base_url }
    AppHosts.define_singleton_method(:configured_api_base_url) { api_base_url }
    @split_hosts_stubbed = true
  end

  test "not split without admin_base_url: every section is served on any host" do
    stub_hosts_without_redrawing(admin_base_url: nil)
    request = Struct.new(:host).new("anything.example")

    assert_not AppHosts.split?
    %i[public admin api].each { |section| assert AppHosts.serves_request?(section, request) }
    assert_equal({}, AppHosts.public_url_options)
  end

  test "api_base_url falls back to the public URL" do
    stub_llmarkt_config(app_base_url: "https://khabarestan.com")
    assert_equal "https://khabarestan.com", AppHosts.api_base_url

    stub_hosts_without_redrawing(admin_base_url: nil, api_base_url: "https://api.khabarestan.com")
    assert_equal "https://api.khabarestan.com", AppHosts.api_base_url
  end

  test "without an API host, /api/* stays on the public host when split" do
    stub_hosts_without_redrawing(admin_base_url: "https://admin.khabarestan.com")

    assert AppHosts.serves_request?(:api, Struct.new(:host).new("khabarestan.com"))
    assert_not AppHosts.serves_request?(:api, Struct.new(:host).new("admin.khabarestan.com"))
  end

  test "the www / bare-domain twin of the public host" do
    stub_llmarkt_config(app_base_url: "https://www.khabarestan.com")
    assert_equal "khabarestan.com", AppHosts.public_host_alias

    stub_llmarkt_config(app_base_url: "https://khabarestan.com")
    assert_equal "www.khabarestan.com", AppHosts.public_host_alias
  end

  test "AppRole rejects unknown roles and the worker serves only its status page" do
    ENV["APP_ROLE"] = "worker"
    assert AppRole.worker?
    assert AppRole.web_server_runs_pollers?
    assert AppRole.serves?(:worker)
    %i[public admin api].each { |section| assert_not AppRole.serves?(section) }

    ENV["APP_ROLE"] = "adminn"
    assert_raises(ArgumentError) { AppRole.current }
  end
end
