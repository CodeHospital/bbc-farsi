require "test_helper"

class Admin::PendingEditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @restricted_editor = create_editor_user(requires_edit_approval: true)
    @translation       = create_translation(attrs: { translated_title: "عنوان قدیم", translated_body: "متن قدیم" })
    stub_article_image_lookup
  end

  teardown { restore_article_image_lookup }

  test "restricted editor's translation update is queued, not applied" do
    log_in_as(@restricted_editor)

    assert_difference("PendingEdit.pending.count", 1) do
      patch admin_translation_path(@translation), params: { translation: { translated_title: "عنوان جدید", translated_body: "متن قدیم" } }
    end
    assert_redirected_to admin_translation_path(@translation)
    assert_equal "عنوان قدیم", @translation.reload.translated_title
    assert_equal @restricted_editor, PendingEdit.last.author
  end

  test "restricted editor's rewrite update is queued, not applied" do
    rewrite = create_rewrite(attrs: { content: "Old content." })
    log_in_as(@restricted_editor)

    assert_difference("PendingEdit.pending.count", 1) do
      patch admin_rewrite_path(rewrite), params: { rewrite: { content: "New content." } }
    end
    assert_equal "Old content.", rewrite.reload.content
  end

  test "unchanged submission re-renders the form with an error" do
    log_in_as(@restricted_editor)
    assert_no_difference("PendingEdit.count") do
      patch admin_translation_path(@translation), params: { translation: { translated_title: "عنوان قدیم", translated_body: "متن قدیم" } }
    end
    assert_response :unprocessable_entity
  end

  test "edit form for a restricted editor shows the approval notice and their pending text" do
    PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "پیشنهاد من" })
    log_in_as(@restricted_editor)

    get edit_admin_translation_path(@translation)
    assert_response :success
    assert_select "input[type=submit][value=?]", "Submit for approval"
    assert_select "input[name='translation[translated_title]'][value=?]", "پیشنهاد من"
  end

  test "unrestricted editor still saves directly" do
    log_in_as(create_editor_user)
    assert_no_difference("PendingEdit.count") do
      patch admin_translation_path(@translation), params: { translation: { translated_title: "مستقیم" } }
    end
    assert_equal "مستقیم", @translation.reload.translated_title
  end

  test "reviewer sees the queue and the diff, then approves" do
    pending_edit = PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "عنوان جدید" })
    log_in_as(create_editor_user)

    get admin_pending_edits_path
    assert_response :success
    assert_select "a[href=?]", admin_pending_edit_path(pending_edit)

    get admin_pending_edit_path(pending_edit)
    assert_response :success
    assert_select "del.diff-delete", text: "قدیم"
    assert_select "ins.diff-insert", text: "جدید"

    post approve_admin_pending_edit_path(pending_edit), params: { review_note: "OK" }
    assert_redirected_to admin_pending_edits_path
    assert_equal "عنوان جدید", @translation.reload.translated_title
    assert pending_edit.reload.approved?
  end

  test "reviewer rejects" do
    pending_edit = PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "عنوان جدید" })
    log_in_as

    post reject_admin_pending_edit_path(pending_edit), params: { review_note: "No" }
    assert pending_edit.reload.rejected?
    assert_equal "No", pending_edit.review_note
    assert_equal "عنوان قدیم", @translation.reload.translated_title
  end

  test "restricted editor cannot approve, even their own edit" do
    pending_edit = PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "عنوان جدید" })
    log_in_as(@restricted_editor)

    post approve_admin_pending_edit_path(pending_edit)
    assert_redirected_to admin_pending_edits_path
    assert pending_edit.reload.pending?
  end

  test "restricted editor only sees their own edits" do
    other_restricted_editor = create_editor_user(requires_edit_approval: true)
    others_edit = PendingEdit.submit(@translation, author: other_restricted_editor, attributes: { translated_title: "دیگری" })
    own_edit    = PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "مال من" })
    log_in_as(@restricted_editor)

    get admin_pending_edits_path
    assert_select "a[href=?]", admin_pending_edit_path(own_edit)
    assert_select "a[href=?]", admin_pending_edit_path(others_edit), count: 0

    get admin_pending_edit_path(others_edit)
    assert_response :not_found
  end

  test "author can withdraw their pending edit" do
    pending_edit = PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "عنوان جدید" })
    log_in_as(@restricted_editor)

    assert_difference("PendingEdit.count", -1) { delete admin_pending_edit_path(pending_edit) }
    assert_redirected_to admin_pending_edits_path
  end

  test "admin can flag an editor as needing approval" do
    editor = create_editor_user
    log_in_as
    patch admin_user_path(editor), params: { user: { role: "editor", requires_edit_approval: "1" } }
    assert editor.reload.requires_edit_approval?
  end
end
