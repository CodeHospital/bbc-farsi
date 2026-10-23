require "test_helper"

class ApiLandingControllerTest < ActionDispatch::IntegrationTest
  test "landing page is public and shows processed-task stats" do
    rewrite = create_rewrite
    Task.create!(kind: "rewrite", status: "completed", target: rewrite, model: "secret-model",
                 claimed_at: 90.seconds.ago, completed_at: 30.seconds.ago)
    Task.create!(kind: "translate", status: "failed", target: rewrite, model: "m", error_message: "secret failure")
    Task.create!(kind: "translate", status: "pending", target: rewrite, model: "m")

    get api_landing_path
    assert_response :success
    assert_select "h1", text: "Khabarestan API"
    assert_match "Processed (all time)", response.body
    assert_match "50.0%", response.body
    assert_match "/api/tasks/next", response.body
    assert_no_match "secret-model", response.body
    assert_no_match "secret failure", response.body
  end

  test "JSON carries the same aggregates" do
    get api_landing_path(format: :json)
    assert_response :success
    assert_equal %w[average_processing_seconds_last_24_hours completed_by_kind_last_24_hours completed_per_day generated_at processed queue],
                 response.parsed_body.keys.sort
    assert_equal ApiStats::DAYS_SHOWN, response.parsed_body["completed_per_day"].size
  end

  test "the average processing time is claim-to-complete" do
    Task.create!(kind: "rewrite", status: "completed", target: create_rewrite, model: "m", claimed_at: 100.seconds.ago, completed_at: 40.seconds.ago)
    assert_in_delta 60, ApiStats.compute(Time.current)[:average_processing_seconds_last_24_hours], 2
  end
end
