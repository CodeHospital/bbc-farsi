require "test_helper"

class PromptTest < ActiveSupport::TestCase
  test "seed_defaults! creates every known prompt with a v1 current version" do
    assert_equal Prompt::KEYS.sort, Prompt.pluck(:key).sort

    Prompt::KEYS.each do |key|
      version = Prompt.current_version(key)
      assert_equal 1, version.number
      assert version.content.present?
    end
  end

  test "seed_defaults! is idempotent and never overwrites an edited prompt" do
    prompt = Prompt.find_by!(key: "tag")
    prompt.add_version!("Custom tagging instructions.", user: create_admin_user)

    Prompt.seed_defaults!

    assert_equal "Custom tagging instructions.", Prompt.content_for("tag")
    assert_equal 2, prompt.reload.current_prompt_version.number
  end

  test "add_version! bumps the version number and becomes current" do
    prompt = Prompt.find_by!(key: "feature")
    editor = create_editor_user

    version = prompt.add_version!("New feature-selection wording.", user: editor)

    assert_equal 2, version.number
    assert_equal editor, version.user
    assert_equal version, prompt.reload.current_prompt_version
    assert_equal "New feature-selection wording.", Prompt.content_for("feature")
  end

  test "revert_to! creates a new version copying old content instead of rewinding history" do
    prompt = Prompt.find_by!(key: "translate")
    v1 = prompt.current_prompt_version
    prompt.add_version!("A second draft.", user: create_admin_user)

    reverted = prompt.revert_to!(v1, user: create_admin_user)

    assert_equal 3, reverted.number
    assert_equal v1.content, reverted.content
    assert_match(/Reverted to version #{v1.number}/, reverted.change_note)
    assert_equal 3, prompt.prompt_versions.count
    assert_equal reverted, prompt.reload.current_prompt_version
  end

  test "current_version raises a clear error for an unknown key" do
    assert_raises(ActiveRecord::RecordNotFound) { Prompt.current_version("nonexistent") }
  end
end
