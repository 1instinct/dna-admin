require "test_helper"

class WebhookFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    REDIS.flushdb
    @user = create(:spree_user, email: "jane.doe@example.com")
  end

  test "full MDI PASS → Honeybee RX_RECEIVED flow" do
    mdi_payload = File.read(Rails.root.join("test/fixtures/webhooks/mdi_case_approved.json"))

    post "/api/webhooks/mdi",
      params: mdi_payload,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :ok

    perform_enqueued_jobs(only: ProcessMdiWebhookJob)

    @user.reload
    assert_equal "pass", @user.consultation_status
    assert_equal "enc_test_001", @user.mdi_encounter_id
    assert PendingCustomer.exists?(email: "jane.doe@example.com")

    hb_payload = File.read(Rails.root.join("test/fixtures/webhooks/honeybee_rx_received.json"))

    post "/api/webhooks/honeybee",
      params: hb_payload,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :ok

    perform_enqueued_jobs(only: ProcessHoneybeeWebhookJob)

    assert_equal 1, Prescription.count
    prescription = Prescription.last
    assert_equal "Cntrl+ Pessary Starter Kit", prescription.drug_name
    assert_equal @user, prescription.patient_mapping.spree_user

    mapping = PatientMapping.find_by(honeybee_patient_id: "hb_pat_001")
    assert_not_nil mapping
    assert_equal @user, mapping.spree_user
  end

  test "duplicate MDI webhooks are idempotent" do
    mdi_payload = File.read(Rails.root.join("test/fixtures/webhooks/mdi_case_approved.json"))

    post "/api/webhooks/mdi",
      params: mdi_payload,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :ok

    assert_no_enqueued_jobs(only: ProcessMdiWebhookJob) do
      post "/api/webhooks/mdi",
        params: mdi_payload,
        headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :ok
    end
  end
end
