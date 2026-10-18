require "test_helper"

class Admin::SkipPhrasesControllerTest < ActionDispatch::IntegrationTest
  setup { log_in_as }

  test "editors are redirected away (admin-only)" do
    post admin_logout_path
    log_in_as(create_editor_user)
    get admin_skip_phrases_path
    assert_redirected_to admin_root_path
  end

  test "index lists phrases" do
    get admin_skip_phrases_path
    assert_response :success
    assert_select "code", text: "Watch:"
  end

  test "create adds a phrase" do
    assert_difference("SkipPhrase.count", 1) do
      post admin_skip_phrases_path, params: { skip_phrase: { phrase: "Live blog", match_field: "title" } }
    end
    assert_redirected_to admin_skip_phrases_path
    assert Article.ignorable?("Live blog: day 2", "https://bbc.co.uk/news/a")
  end

  test "create rejects a duplicate" do
    assert_no_difference("SkipPhrase.count") do
      post admin_skip_phrases_path, params: { skip_phrase: { phrase: "watch:", match_field: "title" } }
    end
    assert_response :unprocessable_entity
  end

  test "toggle and destroy" do
    phrase = SkipPhrase.find_by!(phrase: "Watch:")
    patch toggle_admin_skip_phrase_path(phrase)
    assert_not phrase.reload.enabled?
    assert_difference("SkipPhrase.count", -1) { delete admin_skip_phrase_path(phrase) }
  end
end
