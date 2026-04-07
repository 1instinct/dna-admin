class LogWebhookEventJob < ApplicationJob
  queue_as :low

  def perform(event_type:, source:, payload:, correlation_id: nil, error: nil)
    WebhookEvent.create!(
      event_type: event_type,
      source: source,
      payload: payload,
      correlation_id: correlation_id,
      processed_at: Time.current,
      error: error
    )
  end
end
