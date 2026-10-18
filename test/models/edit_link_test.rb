require "test_helper"

class EditLinkTest < ActiveSupport::TestCase
  setup do
    @admin       = create_admin_user
    @translation = create_translation(attrs: { translated_title: "عنوان" })
    @article     = @translation.article
  end

  def build_link(attrs = {})
    @article.edit_links.create!({ created_by: @admin, expires_at: 7.days.from_now }.merge(attrs))
  end

  test "generates a unique secret token" do
    first_link, second_link = build_link, build_link
    assert_operator first_link.token.length, :>=, 20
    assert_not_equal first_link.token, second_link.token
  end

  test "find_usable ignores unknown, revoked and expired tokens" do
    link = build_link
    assert_equal link, EditLink.find_usable(link.token)
    assert_nil EditLink.find_usable("nope")
    assert_nil EditLink.find_usable(nil)

    link.revoke!
    assert_nil EditLink.find_usable(link.token)
    assert_equal "revoked", link.status

    expired = build_link(expires_at: 1.minute.ago)
    assert_nil EditLink.find_usable(expired.token)
    assert_equal "expired", expired.status
  end

  test "translation is the live one, not archived or untitled" do
    link = build_link
    assert_equal @translation, link.translation

    @translation.update!(archived: true)
    assert_nil link.translation
  end

  test "multi-use links are never spent" do
    link = build_link
    assert link.claim_use!
    assert link.claim_use!
    assert link.usable?
    assert_nil link.reload.used_at
  end

  test "a single-use link can be claimed exactly once, then reads as used" do
    link = build_link(single_use: true)
    assert link.claim_use!
    assert_not link.claim_use!, "second claim must lose"

    link.reload
    assert link.used_up?
    assert_not link.usable?
    assert_equal "used", link.status
    assert_nil EditLink.find_usable(link.token)
  end
end
