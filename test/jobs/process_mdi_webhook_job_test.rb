require "test_helper"

class ProcessMdiWebhookJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create(:spree_user, email: "jane.doe@example.com")
    @payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/mdi_case_approved.json"))
    )
  end

  test "PASS: updates user consultation_status to pass" do
    ProcessMdiWebhookJob.perform_now(@payload)
    @user.reload
    assert_equal "pass", @user.consultation_status
    assert_not_nil @user.consultation_completed_at
    assert_equal "enc_test_001", @user.mdi_encounter_id
  end

  test "PASS: creates PendingCustomer record" do
    assert_difference "PendingCustomer.count", 1 do
      ProcessMdiWebhookJob.perform_now(@payload)
    end

    pending = PendingCustomer.last
    assert_equal "jane.doe@example.com", pending.email
    assert_equal "enc_test_001", pending.mdi_encounter_id
  end

  test "case_completed also maps to PASS" do
    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/mdi_case_completed.json"))
    )
    user = create(:spree_user, email: "alice.smith@example.com")

    ProcessMdiWebhookJob.perform_now(payload)
    user.reload
    assert_equal "pass", user.consultation_status
  end

  test "FAIL: updates user consultation_status to fail" do
    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/mdi_case_cancelled.json"))
    )
    user = create(:spree_user, email: "bob@example.com")

    ProcessMdiWebhookJob.perform_now(payload)
    user.reload
    assert_equal "fail", user.consultation_status
  end

  test "PENDING: enqueues RetryPendingEncounterJob" do
    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/mdi_case_pending.json"))
    )
    create(:spree_user, email: "pending@example.com")

    assert_enqueued_with(job: RetryPendingEncounterJob) do
      ProcessMdiWebhookJob.perform_now(payload)
    end
  end

  test "handles missing user gracefully" do
    payload = @payload.deep_dup
    payload["metadata"]["patient"]["email"] = "unknown@example.com"

    assert_nothing_raised do
      ProcessMdiWebhookJob.perform_now(payload)
    end
    assert_equal 1, PendingCustomer.count
  end
end
