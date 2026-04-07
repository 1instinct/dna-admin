require "test_helper"

class WebhookIdempotencyServiceTest < ActiveSupport::TestCase
  setup do
    REDIS.flushdb
  end

  test "first call returns false (not yet processed)" do
    assert_not WebhookIdempotencyService.already_processed?("mdi", "evt_001")
  end

  test "second call returns true (already processed)" do
    WebhookIdempotencyService.already_processed?("mdi", "evt_001")
    assert WebhookIdempotencyService.already_processed?("mdi", "evt_001")
  end

  test "different sources with same event_id are independent" do
    WebhookIdempotencyService.already_processed?("mdi", "evt_001")
    assert_not WebhookIdempotencyService.already_processed?("honeybee", "evt_001")
  end

  test "keys expire after TTL" do
    WebhookIdempotencyService.already_processed?("mdi", "evt_001")
    ttl = REDIS.ttl("webhook:mdi:evt_001")
    assert ttl > 0
    assert ttl <= 86_400
  end

  test "clear! removes a specific key" do
    WebhookIdempotencyService.already_processed?("mdi", "evt_001")
    WebhookIdempotencyService.clear!("mdi", "evt_001")
    assert_not WebhookIdempotencyService.already_processed?("mdi", "evt_001")
  end
end
