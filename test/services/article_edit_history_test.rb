require "test_helper"

class ArticleEditHistoryTest < ActiveSupport::TestCase
  setup do
    @restricted_editor = create_editor_user(requires_edit_approval: true)
    @reviewer          = create_editor_user
    @translation       = create_translation(attrs: { translated_title: "عنوان قدیم" })
    @article           = @translation.article
  end

  def human_edit(user, record, attributes)
    PaperTrail.request(whodunnit: user.id.to_s) { record.update!(attributes) }
  end

  test "lists manual edits with text diffs and hides system changes by default" do
    human_edit(@reviewer, @translation, translated_title: "عنوان دستی")
    @translation.update!(error_message: "system note")

    entries = ArticleEditHistory.new(@article).entries
    assert_equal 1, entries.size
    assert_equal @reviewer.username, entries.first.actor_name
    assert_equal [ "عنوان قدیم", "عنوان دستی" ], entries.first.text_changes["translated_title"]

    history = ArticleEditHistory.new(@article)
    assert_operator history.hidden_system_count, :>=, 1
    assert_operator ArticleEditHistory.new(@article, include_system: true).entries.size, :>, 1
  end

  test "approved proposal appears once, with its reviewer, not duplicated by its version" do
    pending_edit = PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "عنوان جدید" })
    pending_edit.approve!(reviewer: @reviewer, note: "ok")

    entries = ArticleEditHistory.new(@article).entries
    assert_equal 1, entries.size
    entry = entries.first
    assert_equal :proposal, entry.kind
    assert_equal "approved", entry.status
    assert_equal @reviewer.username, entry.reviewer_name
    assert_equal [ "عنوان قدیم", "عنوان جدید" ], entry.text_changes["translated_title"]
  end

  test "rejected and pending proposals are listed" do
    rejected = PendingEdit.submit(@translation, author: @restricted_editor, attributes: { translated_title: "رد شده" })
    rejected.reject!(reviewer: @reviewer)
    other_restricted_editor = create_editor_user(requires_edit_approval: true)
    PendingEdit.submit(@translation, author: other_restricted_editor, attributes: { translated_title: "در انتظار" })

    assert_equal %w[pending rejected], ArticleEditHistory.new(@article).entries.map(&:status).sort
  end
end
