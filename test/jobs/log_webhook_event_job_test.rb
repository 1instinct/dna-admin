require "test_helper"

class LogWebhookEventJobTest < ActiveSupport::TestCase
  test "creates a WebhookEvent record" do
    assert_difference "WebhookEvent.count", 1 do
      LogWebhookEventJob.perform_now(
        event_type: "case_approved",
        source: "mdi",
        payload: { encounter_id: "enc_123" },
        correlation_id: "corr_001"
      )
    end

    event = WebhookEvent.last
    assert_equal "case_approved", event.event_type
    assert_equal "mdi", event.source
    assert_equal "enc_123", event.payload["encounter_id"]
    assert_equal "corr_001", event.correlation_id
    assert_not_nil event.processed_at
  end

  test "stores error if provided" do
    LogWebhookEventJob.perform_now(
      event_type: "RX_RECEIVED",
      source: "honeybee",
      payload: {},
      error: "Processing failed: timeout"
    )

    event = WebhookEvent.last
    assert_equal "Processing failed: timeout", event.error
  end
end
