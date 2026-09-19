require "test_helper"

class SearchQueryTest < ActiveSupport::TestCase
  test "track! records a search" do
    assert_difference("SearchQuery.count", 1) do
      SearchQuery.track!("Tehran", edition: "fa", results_count: 3)
    end
    assert_equal "tehran", SearchQuery.last.keyword
  end

  test "track! swallows errors and reports them to Sentry instead of raising" do
    captured = nil
    Sentry.stub(:capture_exception, ->(e) { captured = e }) do
      SearchQuery.stub(:create!, ->(*) { raise ActiveRecord::StatementInvalid, "no such table" }) do
        assert_nothing_raised { SearchQuery.track!("keyword") }
      end
    end

    assert_kind_of ActiveRecord::StatementInvalid, captured
  end

  test "table_exists? reports a DB error to Sentry and returns false" do
    captured = nil
    Sentry.stub(:capture_exception, ->(e) { captured = e }) do
      SearchQuery.connection.stub(:table_exists?, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
        assert_equal false, SearchQuery.table_exists?
      end
    end

    assert_kind_of ActiveRecord::StatementInvalid, captured
  end
end
