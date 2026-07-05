require "test_helper"

class Admin::PromptsControllerTest < ActionDispatch::IntegrationTest
  setup { @prompt = Prompt.find_by!(key: "tag") }

  test "index lists all prompts" do
    log_in_as
    get admin_prompts_path
    assert_response :success
    assert_select "code", text: "tag"
  end

  test "show renders the current content and version history" do
    log_in_as
    get admin_prompt_path(@prompt)
    assert_response :success
    assert_match "Persian (Farsi) news editor assigning topic tags", response.body
  end

  test "update with changed content creates a new version and redirects" do
    admin = log_in_as
    patch admin_prompt_path(@prompt), params: { prompt: { name: @prompt.name, description: @prompt.description, content: "Brand new tag instructions." } }

    assert_response :redirect
    @prompt.reload
    assert_equal 2, @prompt.current_prompt_version.number
    assert_equal "Brand new tag instructions.", @prompt.current_prompt_version.content
    assert_equal admin, @prompt.current_prompt_version.user
  end

  test "update with unchanged content does not create a noise version" do
    log_in_as
    original_version = @prompt.current_prompt_version

    patch admin_prompt_path(@prompt), params: { prompt: { name: @prompt.name, description: @prompt.description, content: original_version.content } }

    assert_response :redirect
    assert_equal original_version, @prompt.reload.current_prompt_version
  end

  test "revert creates a new version copying an older one's content" do
    log_in_as
    v1 = @prompt.current_prompt_version
    @prompt.add_version!("A second draft.", user: create_admin_user)

    post revert_admin_prompt_path(@prompt, version_id: v1.id)

    assert_response :redirect
    assert_equal v1.content, @prompt.reload.current_prompt_version.content
    assert_equal 3, @prompt.prompt_versions.count
  end

  test "editors can edit prompts (not admin-only)" do
    log_in_as(create_editor_user)

    get edit_admin_prompt_path(@prompt)
    assert_response :success

    patch admin_prompt_path(@prompt), params: { prompt: { name: @prompt.name, description: @prompt.description, content: "Editor-written instructions." } }
    assert_response :redirect
    assert_equal "Editor-written instructions.", @prompt.reload.current_prompt_version.content
  end
end
