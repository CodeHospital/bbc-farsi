require "test_helper"

class RewriteTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    assert create_rewrite.valid?
  end

  test "invalid with unknown status" do
    rewrite = create_rewrite
    rewrite.status = "bogus"
    assert_not rewrite.valid?
  end

  test "completed scope returns only completed rewrites" do
    done    = create_rewrite(attrs: { status: "completed" })
    running = create_rewrite(attrs: { status: "running" })
    assert_includes Rewrite.completed, done
    assert_not_includes Rewrite.completed, running
  end

  test "activate! marks rewrite as active and deactivates siblings" do
    article  = create_article
    first    = create_rewrite(article:, attrs: { active: true })
    second   = create_rewrite(article:)

    second.activate!

    assert second.reload.active?
    assert_not first.reload.active?
  end

  test "active_version scope returns only active rewrite" do
    article = create_article
    active  = create_rewrite(article:, attrs: { active: true })
    _other  = create_rewrite(article:, attrs: { active: false })

    assert_includes Rewrite.active_version, active
    assert_equal 1, article.rewrites.active_version.count
  end
end
