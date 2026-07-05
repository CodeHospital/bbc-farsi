require "test_helper"

class TranslationTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    assert create_translation.valid?
  end

  test "invalid with unknown status" do
    t = create_translation
    t.status = "bogus"
    assert_not t.valid?
  end

  test "completed scope returns only completed translations" do
    done    = create_translation(attrs: { status: "completed" })
    pending = create_translation(attrs: { status: "pending" })
    assert_includes Translation.completed, done
    assert_not_includes Translation.completed, pending
  end

  test "activate! marks translation as active and deactivates siblings" do
    article  = create_article
    rewrite  = create_rewrite(article:)
    first    = create_translation(rewrite:, attrs: { active: true })
    second   = create_translation(rewrite:)

    second.activate!

    assert second.reload.active?
    assert_not first.reload.active?
  end

  test "active_version scope returns only active translation" do
    article  = create_article
    rewrite  = create_rewrite(article:)
    active   = create_translation(rewrite:, attrs: { active: true })
    _other   = create_translation(rewrite:, attrs: { active: false })

    assert_includes Translation.active_version, active
    assert_equal 1, article.translations.active_version.count
  end

  test "unposted_for excludes already-posted translations" do
    channel     = create_channel
    translation = create_translation
    TelegramPost.create!(translation:, telegram_channel: channel, status: "posted", posted_at: Time.current)

    assert_not_includes Translation.completed.unposted_for(channel), translation
  end

  test "unposted_for includes translations not posted to that channel" do
    channel     = create_channel
    translation = create_translation
    assert_includes Translation.completed.unposted_for(channel), translation
  end

  test "mark_for_manual_edit! and clear_manual_edit! toggle the flag" do
    translation = create_translation(attrs: { needs_manual_edit: false })

    translation.mark_for_manual_edit!
    assert translation.reload.needs_manual_edit?

    translation.clear_manual_edit!
    assert_not translation.reload.needs_manual_edit?
  end

  test "needs_manual_edit scope returns only flagged translations" do
    flagged   = create_translation(attrs: { needs_manual_edit: true })
    unflagged = create_translation(attrs: { needs_manual_edit: false })

    assert_includes Translation.needs_manual_edit, flagged
    assert_not_includes Translation.needs_manual_edit, unflagged
  end
end
