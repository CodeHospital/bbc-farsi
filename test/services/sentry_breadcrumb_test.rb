require "test_helper"

class SentryBreadcrumbTest < ActiveSupport::TestCase
  test "record sends a Sentry::Breadcrumb with the given message, category, data and level" do
    recorded_breadcrumbs = []
    recording_add_breadcrumb = ->(breadcrumb, **options) do
      assert_empty options
      recorded_breadcrumbs << breadcrumb
    end

    Sentry.stub(:add_breadcrumb, recording_add_breadcrumb) do
      SentryBreadcrumb.record("Step.one", category: "step", data: { id: 7 }, level: "warning")
    end

    breadcrumb = recorded_breadcrumbs.sole
    assert_instance_of Sentry::Breadcrumb, breadcrumb
    assert_equal "Step.one", breadcrumb.message
    assert_equal "step", breadcrumb.category
    assert_equal({ id: 7 }, breadcrumb.data)
    assert_equal "warning", breadcrumb.level
  end

  test "record falls back to the app category and info level" do
    recorded_breadcrumbs = []
    recording_add_breadcrumb = ->(breadcrumb, **_options) { recorded_breadcrumbs << breadcrumb }

    Sentry.stub(:add_breadcrumb, recording_add_breadcrumb) do
      SentryBreadcrumb.record("Step.two")
    end

    breadcrumb = recorded_breadcrumbs.sole
    assert_equal "app", breadcrumb.category
    assert_equal "info", breadcrumb.level
    assert_equal({}, breadcrumb.data)
  end
end
