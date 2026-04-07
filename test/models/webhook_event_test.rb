require "test_helper"

class WebhookEventTest < ActiveSupport::TestCase
  test "valid webhook event" do
    event = build(:webhook_event)
    assert event.valid?
  end

  test "requires event_type" do
    event = build(:webhook_event, event_type: nil)
    assert_not event.valid?
  end

  test "requires source" do
    event = build(:webhook_event, source: nil)
    assert_not event.valid?
  end

  test "valid source values" do
    %w[mdi honeybee internal].each do |source|
      event = build(:webhook_event, source: source)
      assert event.valid?, "Expected #{source} to be valid"
    end
  end
end
