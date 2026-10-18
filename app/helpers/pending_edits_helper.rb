module PendingEditsHelper
  PENDING_EDIT_ATTRIBUTE_LABELS = {
    "translated_title" => "Title",
    "translated_body"  => "Body",
    "content"          => "Rewritten content"
  }.freeze

  PENDING_EDIT_STATUS_BADGE_CLASSES = {
    "pending"  => "bg-warning text-dark",
    "approved" => "bg-success",
    "rejected" => "bg-danger"
  }.freeze

  # Sidebar badge: the review queue size for reviewers, the user's own
  # still-pending edits for restricted editors. Memoized per request.
  def pending_edit_sidebar_count
    @pending_edit_sidebar_count ||=
      if current_user.nil?
        0
      elsif current_user.can_review_edits?
        PendingEdit.pending.count
      else
        PendingEdit.pending.where(author: current_user).count
      end
  end

  def pending_edit_attribute_label(attribute_name)
    PENDING_EDIT_ATTRIBUTE_LABELS.fetch(attribute_name, attribute_name.humanize)
  end

  def pending_edit_status_badge(pending_edit)
    tag.span(pending_edit.status, class: "badge #{PENDING_EDIT_STATUS_BADGE_CLASSES[pending_edit.status]}")
  end

  # Persian translation text is RTL; rewrites are English.
  def pending_edit_text_direction(pending_edit)
    pending_edit.editable_type == "Translation" ? { dir: "rtl", lang: "fa" } : {}
  end

  def pending_edit_record_label(pending_edit)
    "#{pending_edit.editable_type} ##{pending_edit.editable_id}"
  end

  def pending_edit_record_path(pending_edit)
    case pending_edit.editable_type
    when "Translation" then admin_translation_path(pending_edit.editable_id)
    when "Rewrite"     then admin_rewrite_path(pending_edit.editable_id)
    end
  end

  # Inline word diff: removed words struck through in red, added words
  # highlighted in green. Text is escaped by `tag`/`safe_join`.
  def word_diff_html(old_text, new_text)
    diff_pieces = TextDiff.word_diff(old_text, new_text).map do |operation, text|
      case operation
      when :equal  then text
      when :delete then tag.del(text, class: "diff-delete")
      when :insert then tag.ins(text, class: "diff-insert")
      end
    end
    safe_join(diff_pieces)
  end

  # Link target for a timeline entry's Translation/Rewrite.
  def edit_history_record_path(entry)
    case entry.record_type
    when "Translation" then admin_translation_path(entry.record_id)
    when "Rewrite"     then admin_rewrite_path(entry.record_id)
    end
  end

  def edit_history_text_direction(entry)
    entry.record_type == "Translation" ? { dir: "rtl", lang: "fa" } : {}
  end

  # "🇩🇪 Aachen, Germany" for a guest edit's resolved location, "Unknown
  # location" when the IP couldn't be located (e.g. private/local address).
  def pending_edit_location_label(pending_edit)
    return "Unknown location" if pending_edit.guest_location.blank?

    "#{country_flag(pending_edit.guest_country_name)} #{pending_edit.guest_location}"
  end
end
