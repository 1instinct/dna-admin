require "test_helper"
require "webmock/minitest"

class RetryPendingEncounterJobTest < ActiveSupport::TestCase
  setup do
    ENV["MDI_API_BASE"] = "https://api.mdintegrations.com/v1"
    ENV["MDI_CLIENT_ID"] = "test_client_id"
    ENV["MDI_CLIENT_SECRET"] = "test_client_secret"

    @user = create(:spree_user, email: "retry@example.com", consultation_status: :pending)
  end

  test "resolves to PASS when MDI returns approved" do
    stub_request(:get, "https://api.mdintegrations.com/v1/encounters/enc_retry")
      .to_return(
        status: 200,
        body: { id: "enc_retry", status: "PASS" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    RetryPendingEncounterJob.perform_now("enc_retry", "retry@example.com")
    @user.reload
    assert_equal "pass", @user.consultation_status
  end

  test "resolves to FAIL when MDI returns cancelled" do
    stub_request(:get, "https://api.mdintegrations.com/v1/encounters/enc_retry")
      .to_return(
        status: 200,
        body: { id: "enc_retry", status: "FAIL" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    RetryPendingEncounterJob.perform_now("enc_retry", "retry@example.com")
    @user.reload
    assert_equal "fail", @user.consultation_status
  end

  test "raises PendingError when still pending" do
    stub_request(:get, "https://api.mdintegrations.com/v1/encounters/enc_retry")
      .to_return(
        status: 200,
        body: { id: "enc_retry", status: "PENDING" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_raises(MdiClient::PendingError) do
      RetryPendingEncounterJob.perform_now("enc_retry", "retry@example.com")
    end
  end
end
