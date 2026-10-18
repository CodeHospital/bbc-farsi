require "test_helper"

class GuestEditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin       = create_admin_user
    @translation = create_translation(attrs: { translated_title: "عنوان قدیم", translated_body: "متن قدیم" })
    @edit_link   = @translation.article.edit_links.create!(created_by: @admin, expires_at: 7.days.from_now, note: "Sara")
  end

  def guest_params(overrides = {})
    { guest_name: "Sara Test", guest_email: "Sara@Example.com", guest_phone: "+49 241 123456",
      translated_title: "عنوان جدید", translated_body: "متن قدیم", consent: "1" }.merge(overrides)
  end

  test "valid link shows the form with the current text, no-index and no-referrer" do
    get guest_edit_path(@edit_link.token)
    assert_response :success
    assert_select "input[name=translated_title][value=?]", "عنوان قدیم"
    assert_select "input[name=guest_phone]"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_match(/noindex/, response.headers["X-Robots-Tag"])
  end

  test "unknown, revoked and expired links all 404 with the same page" do
    get guest_edit_path("bogus")
    assert_response :not_found
    @edit_link.revoke!
    get guest_edit_path(@edit_link.token)
    assert_response :not_found
    expired = @translation.article.edit_links.create!(created_by: @admin, expires_at: 1.minute.ago)
    get guest_edit_path(expired.token)
    assert_response :not_found
  end

  test "submitting creates a guest pending edit and leaves the live text alone" do
    assert_difference("PendingEdit.pending.count", 1) { post guest_edit_path(@edit_link.token), params: guest_params }
    assert_redirected_to guest_edit_thanks_path(@edit_link.token)

    pending_edit = PendingEdit.last
    assert pending_edit.guest?
    assert_equal @edit_link, pending_edit.edit_link
    assert_equal "Sara Test", pending_edit.guest_name
    assert_equal "sara@example.com", pending_edit.guest_email
    assert_equal({ "translated_title" => "عنوان جدید" }, pending_edit.proposed_changes)
    assert_equal "عنوان قدیم", @translation.reload.translated_title
  end

  test "resubmitting with the same email updates the same pending edit" do
    post guest_edit_path(@edit_link.token), params: guest_params
    assert_no_difference("PendingEdit.count") do
      post guest_edit_path(@edit_link.token), params: guest_params(translated_title: "نسخه دوم")
    end
    assert_equal "نسخه دوم", PendingEdit.last.proposed_changes["translated_title"]
  end

  test "missing contact details or consent re-render the form without saving" do
    assert_no_difference("PendingEdit.count") do
      post guest_edit_path(@edit_link.token), params: guest_params(guest_phone: "")
      assert_response :unprocessable_entity
      post guest_edit_path(@edit_link.token), params: guest_params(guest_email: "not-an-email")
      assert_response :unprocessable_entity
      post guest_edit_path(@edit_link.token), params: guest_params(consent: "0")
      assert_response :unprocessable_entity
      post guest_edit_path(@edit_link.token), params: guest_params(translated_title: "عنوان قدیم")
      assert_response :unprocessable_entity
    end
  end

  test "honeypot submissions are silently dropped" do
    assert_no_difference("PendingEdit.count") do
      post guest_edit_path(@edit_link.token), params: guest_params(website: "http://spam.example")
    end
    assert_redirected_to guest_edit_thanks_path(@edit_link.token)
  end

  test "revoked link cannot submit" do
    @edit_link.revoke!
    assert_no_difference("PendingEdit.count") { post guest_edit_path(@edit_link.token), params: guest_params }
    assert_response :not_found
  end

  test "reviewer sees guest details and approving publishes under the guest's name" do
    post guest_edit_path(@edit_link.token), params: guest_params
    pending_edit = PendingEdit.last

    log_in_as(@admin)
    get admin_pending_edit_path(pending_edit)
    assert_response :success
    assert_match "Sara Test (guest)", response.body
    assert_match "sara@example.com", response.body
    assert_match "+49 241 123456", response.body

    post approve_admin_pending_edit_path(pending_edit)
    assert_equal "عنوان جدید", @translation.reload.translated_title
    assert_equal "guest:Sara Test", @translation.versions.last.whodunnit

    get admin_article_path(@translation.article)
    assert_select "#edit_history strong", text: "Sara Test (guest)"
  end

  def stub_ipwho(ip, country: "Germany", city: "Aachen")
    stub_request(:get, %r{\Ahttps://ipwho\.is/#{Regexp.escape(ip)}\?})
      .to_return(body: { success: true, country:, city: }.to_json)
  end

  test "records the submitter's IP and the location it resolves to" do
    stub_ipwho("203.0.113.9")
    post guest_edit_path(@edit_link.token), params: guest_params, headers: { "REMOTE_ADDR" => "203.0.113.9" }

    pending_edit = PendingEdit.last
    assert_equal "203.0.113.9", pending_edit.guest_ip
    assert_equal "Germany", pending_edit.guest_country_name
    assert_equal "Aachen", pending_edit.guest_city_name
    assert_equal "Aachen, Germany", pending_edit.guest_location

    log_in_as(@admin)
    get admin_pending_edit_path(pending_edit)
    assert_match "203.0.113.9", response.body
    assert_match "Aachen, Germany", response.body
    get admin_pending_edits_path
    assert_match "Aachen, Germany", response.body
  end

  test "a failed location lookup still saves the edit with the IP" do
    stub_request(:get, %r{ipwho\.is}).to_return(status: 500, body: "boom")
    post guest_edit_path(@edit_link.token), params: guest_params, headers: { "REMOTE_ADDR" => "203.0.113.10" }

    pending_edit = PendingEdit.last
    assert_equal "203.0.113.10", pending_edit.guest_ip
    assert_nil pending_edit.guest_location
  end

  test "local addresses are recorded without a lookup" do
    post guest_edit_path(@edit_link.token), params: guest_params
    assert_equal "127.0.0.1", PendingEdit.last.guest_ip
    assert_nil PendingEdit.last.guest_location
  end

  test "multi-use link accepts several different people" do
    post guest_edit_path(@edit_link.token), params: guest_params
    assert_difference("PendingEdit.count", 1) do
      post guest_edit_path(@edit_link.token), params: guest_params(guest_name: "Reza", guest_email: "reza@example.com")
    end
    assert_equal 2, @edit_link.pending_edits.count
    assert @edit_link.reload.usable?
  end

  test "single-use link is spent by the first submission, then closed to everyone" do
    single_use_link = @translation.article.edit_links.create!(created_by: @admin, expires_at: 7.days.from_now, single_use: true)

    post guest_edit_path(single_use_link.token), params: guest_params
    assert_redirected_to guest_edit_thanks_path(single_use_link.token)
    assert single_use_link.reload.used_up?

    follow_redirect!
    assert_response :success
    assert_select "a", text: "Make another change", count: 0

    get guest_edit_path(single_use_link.token)
    assert_response :not_found
    assert_no_difference("PendingEdit.count") do
      post guest_edit_path(single_use_link.token), params: guest_params(guest_email: "other@example.com")
    end
    assert_response :not_found
  end

  test "an invalid submission does not spend a single-use link" do
    single_use_link = @translation.article.edit_links.create!(created_by: @admin, expires_at: 7.days.from_now, single_use: true)
    post guest_edit_path(single_use_link.token), params: guest_params(guest_phone: "")
    assert_response :unprocessable_entity
    assert single_use_link.reload.usable?
  end
end
