require "test_helper"

class PendingEditTest < ActiveSupport::TestCase
  setup do
    @author      = create_editor_user(requires_edit_approval: true)
    @reviewer    = create_editor_user
    @translation = create_translation(attrs: { translated_title: "عنوان قدیم", translated_body: "متن قدیم" })
  end

  test "submit stores only changed attributes plus a snapshot of their current values" do
    pending_edit = PendingEdit.submit(@translation, author: @author,
                                      attributes: { translated_title: "عنوان جدید", translated_body: "متن قدیم" })

    assert pending_edit.persisted?
    assert_equal({ "translated_title" => "عنوان جدید" }, pending_edit.proposed_changes)
    assert_equal({ "translated_title" => "عنوان قدیم" }, pending_edit.base_values)
    assert_equal "عنوان قدیم", @translation.reload.translated_title, "live record must not change"
  end

  test "submit ignores attributes outside the approval allowlist" do
    pending_edit = PendingEdit.submit(@translation, author: @author,
                                      attributes: { translated_title: "عنوان جدید", status: "error" })
    assert_equal [ "translated_title" ], pending_edit.proposed_changes.keys
  end

  test "submit with no actual change is invalid" do
    pending_edit = PendingEdit.submit(@translation, author: @author, attributes: { translated_title: "عنوان قدیم" })
    assert_not pending_edit.persisted?
    assert pending_edit.errors[:base].any?
  end

  test "resubmitting updates the author's existing pending edit and keeps the original snapshot" do
    first_edit = PendingEdit.submit(@translation, author: @author, attributes: { translated_title: "نسخه یک" })
    @translation.update!(translated_title: "تغییر دیگران")

    assert_no_difference("PendingEdit.count") do
      PendingEdit.submit(@translation, author: @author, attributes: { translated_title: "نسخه دو" })
    end
    first_edit.reload
    assert_equal "نسخه دو", first_edit.proposed_changes["translated_title"]
    assert_equal "عنوان قدیم", first_edit.base_values["translated_title"]
    assert_equal [ "translated_title" ], first_edit.conflicting_attribute_names
  end

  test "approve! applies the change, attributes the version to the author, and records the reviewer" do
    pending_edit = PendingEdit.submit(@translation, author: @author, attributes: { translated_body: "متن جدید" })
    pending_edit.approve!(reviewer: @reviewer, note: "خوب است")

    assert_equal "متن جدید", @translation.reload.translated_body
    assert pending_edit.reload.approved?
    assert_equal @reviewer, pending_edit.reviewer
    assert_equal "خوب است", pending_edit.review_note
    assert_not_nil pending_edit.reviewed_at
    assert_equal @author.id.to_s, @translation.versions.last.whodunnit
  end

  test "reject! leaves the record untouched" do
    pending_edit = PendingEdit.submit(@translation, author: @author, attributes: { translated_body: "متن جدید" })
    pending_edit.reject!(reviewer: @reviewer)

    assert_equal "متن قدیم", @translation.reload.translated_body
    assert pending_edit.reload.rejected?
  end

  test "an already-reviewed edit can't be approved again" do
    pending_edit = PendingEdit.submit(@translation, author: @author, attributes: { translated_body: "متن جدید" })
    pending_edit.reject!(reviewer: @reviewer)
    assert_raises(PendingEdit::NotPending) { pending_edit.approve!(reviewer: @reviewer) }
  end

  test "works for rewrites" do
    rewrite      = create_rewrite(attrs: { content: "Old content." })
    pending_edit = PendingEdit.submit(rewrite, author: @author, attributes: { content: "New content." })
    pending_edit.approve!(reviewer: @reviewer)
    assert_equal "New content.", rewrite.reload.content
  end

  test "user approval flags: admins are never restricted" do
    assert @author.edits_need_approval?
    assert_not @author.can_review_edits?
    assert @reviewer.can_review_edits?
    assert_not create_admin_user(requires_edit_approval: true).edits_need_approval?
  end
end
