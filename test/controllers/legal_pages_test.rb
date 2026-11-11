require "test_helper"

class LegalPagesTest < ActionDispatch::IntegrationTest
  test "Persian terms and privacy pages render at the site root" do
    get "/terms"
    assert_response :success
    assert_select "html[lang=fa][dir=rtl]"
    assert_select "h1", text: "شرایط استفاده"

    get "/privacy"
    assert_response :success
    assert_select "h1", text: "سیاست حریم خصوصی"
    assert_no_match(/Aralel|Aachen|Germany|GDPR/, response.body)
  end

  test "English edition lives under /en" do
    get "/en/terms"
    assert_response :success
    assert_select "h1", text: "Terms of Use"

    get "/en/privacy"
    assert_response :success
    assert_select "h1", text: "Privacy Policy"
    assert_select "a[href=?]", "/terms", text: "Terms of Use", count: 0
    assert_select "a[href=?]", "/en/terms"
  end

  test "contact e-mail shows only when the credential is set" do
    get "/en/privacy"
    assert_select "a[href^='mailto:']", count: 0

    stub_credentials(contact_email: "legal@example.com")
    get "/en/privacy"
    assert_select "a[href='mailto:legal@example.com']"
  end

  test "every public page footer links to both legal pages and the sitemap lists them" do
    get "/"
    assert_select "footer a[href='/terms']"
    assert_select "footer a[href='/privacy']"

    get "/sitemap.xml"
    assert_match %r{/terms</loc>}, response.body
    assert_match %r{hreflang="en" href="[^"]*/en/privacy"}, response.body
  end
end
