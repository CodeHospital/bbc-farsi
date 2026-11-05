require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "needs at least one name and normalizes names" do
    refute Tag.new(name_fa: " ", name_en: "").valid?

    tag = Tag.create!(name_fa: "  #ایران ", name_en: " Iran  ")
    assert_equal [ "ایران", "Iran" ], [ tag.name_fa, tag.name_en ]
  end

  test "names are unique (English case-insensitively)" do
    Tag.create!(name_fa: "ایران", name_en: "Iran")

    refute Tag.new(name_fa: "ایران").valid?
    refute Tag.new(name_en: "IRAN").valid?
  end

  test "resolve finds a tag by either name and fills in the missing one" do
    persian_only = Tag.create!(name_fa: "ایران")

    assert_equal persian_only, Tag.resolve(name_fa: "ایران", name_en: "Iran")
    assert_equal "Iran", persian_only.reload.name_en
    assert_equal persian_only, Tag.resolve(name_en: "iran")
    assert_nil Tag.resolve(name_fa: "", name_en: nil)
    assert_difference("Tag.count") { Tag.resolve(name_fa: "نفت", name_en: "Oil") }
  end

  test "resolve does not steal a name another tag already owns" do
    oil_tag = Tag.create!(name_fa: "نفت", name_en: "Oil")
    english_only = Tag.create!(name_en: "Petroleum")

    assert_equal oil_tag, Tag.resolve(name_fa: "نفت", name_en: "Petroleum")
    assert_equal "Oil", oil_tag.reload.name_en
    assert_nil english_only.reload.name_fa
  end

  test "name_for picks the edition's language" do
    tag = Tag.new(name_fa: "ایران", name_en: "Iran")
    assert_equal "ایران", tag.name_for("fa")
    assert_equal "Iran", tag.name_for("en")
  end
end
