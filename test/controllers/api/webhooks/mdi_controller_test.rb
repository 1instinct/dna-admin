require "test_helper"

class Api::Webhooks::MdiControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    REDIS.flushdb
    @payload = File.read(Rails.root.join("test/fixtures/webhooks/mdi_case_approved.json"))
  end

  test "POST /api/webhooks/mdi returns 200" do
    post "/api/webhooks/mdi",
      params: @payload,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :ok
  end

  test "POST /api/webhooks/mdi enqueues ProcessMdiWebhookJob" do
    assert_enqueued_with(job: ProcessMdiWebhookJob) do
      post "/api/webhooks/mdi",
        params: @payload,
        headers: { "CONTENT_TYPE" => "application/json" }
    end
  end

  test "POST /api/webhooks/mdi enqueues LogWebhookEventJob" do
    assert_enqueued_with(job: LogWebhookEventJob) do
      post "/api/webhooks/mdi",
        params: @payload,
        headers: { "CONTENT_TYPE" => "application/json" }
    end
  end

  test "POST /api/webhooks/mdi skips duplicate events" do
    post "/api/webhooks/mdi",
      params: @payload,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_no_enqueued_jobs(only: ProcessMdiWebhookJob) do
      post "/api/webhooks/mdi",
        params: @payload,
        headers: { "CONTENT_TYPE" => "application/json" }
    end
  end

  test "POST /api/webhooks/mdi returns 200 for informational events" do
    informational = { event_type: "system_health", timestamp: Time.current.to_i }.to_json
    post "/api/webhooks/mdi",
      params: informational,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :ok
  end
end
