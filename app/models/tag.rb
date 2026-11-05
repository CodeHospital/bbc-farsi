# A bilingual article tag. Every tag has a Persian (`name_fa`) and an English
# (`name_en`) name; AI tagging may create a tag with only one of them, which an
# admin/editor then completes on the Tags admin page. The public portal shows
# each tag in the edition's language and skips tags without a name in it.
#
# Not to be confused with a story's feed tag: every story's default tag is the
# feed it was taken from, derived from Feed#name / Feed#name_fa (see
# NewsHelper#feed_tag_label), so it is never stored here.
class Tag < ApplicationRecord
  has_paper_trail

  has_many :article_tags, dependent: :destroy
  has_many :articles, through: :article_tags

  normalizes :name_fa, :name_en, with: ->(name) { name.to_s.strip.delete_prefix("#").squish.presence }

  validates :name_fa, uniqueness: true, allow_nil: true
  validates :name_en, uniqueness: { case_sensitive: false }, allow_nil: true
  validate :has_a_name

  scope :missing_translation, -> { where(name_fa: nil).or(where(name_en: nil)) }
  scope :alphabetical, -> { order(Arel.sql("COALESCE(name_fa, name_en)")) }

  # Persian characters (Arabic script blocks, incl. presentation forms).
  PERSIAN_SCRIPT = /[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]/

  # Finds the tag matching either name (Persian exactly, English
  # case-insensitively) or creates it, filling in a missing name on an existing
  # tag. Returns nil when both names are blank.
  def self.resolve(name_fa: nil, name_en: nil)
    candidate = new(name_fa:, name_en:)
    return if candidate.name_fa.nil? && candidate.name_en.nil?

    existing_tag = (candidate.name_fa && find_by(name_fa: candidate.name_fa)) ||
                   (candidate.name_en && where("LOWER(name_en) = ?", candidate.name_en.downcase).first)
    return create!(name_fa: candidate.name_fa, name_en: candidate.name_en) unless existing_tag

    # Complete a half-translated tag, unless another tag already owns that name.
    if existing_tag.name_fa.nil? && candidate.name_fa && !exists?(name_fa: candidate.name_fa)
      existing_tag.name_fa = candidate.name_fa
    end
    if existing_tag.name_en.nil? && candidate.name_en && !where("LOWER(name_en) = ?", candidate.name_en.downcase).exists?
      existing_tag.name_en = candidate.name_en
    end
    existing_tag.save! if existing_tag.changed?
    existing_tag
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
    # Lost a race with a concurrent create of the same name — use the winner.
    Sentry.capture_exception(error)
    find_by(name_fa: candidate.name_fa) || where("LOWER(name_en) = ?", candidate.name_en.to_s.downcase).first || raise
  end

  # The name for a portal edition ("fa"/"en"); nil when not translated yet.
  def name_for(language) = language.to_s == "en" ? name_en : name_fa

  # Both names for admin screens, e.g. "ایران / Iran".
  def display_name = [ name_fa, name_en ].compact.join(" / ")

  def missing_translation? = name_fa.nil? || name_en.nil?

  private

  def has_a_name
    errors.add(:base, "A tag needs a Persian or an English name.") if name_fa.nil? && name_en.nil?
  end
end
