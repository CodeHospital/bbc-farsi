# Shared display helpers for PaperTrail::Version rows — used by the
# system-wide activity log and by the per-record "edit history" panels on
# Rewrites/Translations.
module VersionsHelper
  def version_actor(version)
    return "AI worker / system" if version.whodunnit.blank?
    User.find_by(id: version.whodunnit)&.username || "Deleted user ##{version.whodunnit}"
  end

  # Link to the record's admin page, or nil when the record has since been
  # destroyed or has no dedicated admin page.
  def version_record_path(version)
    return nil unless version.item

    case version.item_type
    when "Rewrite"         then admin_rewrite_path(version.item)
    when "Translation"     then admin_translation_path(version.item)
    when "Article"         then admin_article_path(version.item)
    when "Feed"             then edit_admin_feed_path(version.item)
    when "TelegramChannel" then edit_admin_telegram_channel_path(version.item)
    when "OllamaServer"    then edit_admin_ollama_server_path(version.item)
    when "User"            then edit_admin_user_path(version.item)
    end
  end
end
