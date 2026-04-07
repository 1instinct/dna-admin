require "test_helper"

class Api::Webhooks::HoneybeeControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    REDIS.flushdb
    @payload = File.read(Rails.root.join("test/fixtures/webhooks/honeybee_rx_received.json"))
  end

  test "POST /api/webhooks/honeybee returns 200" do
    post "/api/webhooks/honeybee",
      params: @payload,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :ok
  end

  test "POST /api/webhooks/honeybee enqueues ProcessHoneybeeWebhookJob" do
    assert_enqueued_with(job: ProcessHoneybeeWebhookJob) do
      post "/api/webhooks/honeybee",
        params: @payload,
        headers: { "CONTENT_TYPE" => "application/json" }
    end
  end

  test "POST /api/webhooks/honeybee skips duplicate events" do
    post "/api/webhooks/honeybee",
      params: @payload,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_no_enqueued_jobs(only: ProcessHoneybeeWebhookJob) do
      post "/api/webhooks/honeybee",
        params: @payload,
        headers: { "CONTENT_TYPE" => "application/json" }
    end
  end
end
