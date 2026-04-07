module Api
  module Webhooks
    class HoneybeeController < BaseController
      before_action -> { verify_hmac!("HONEYBEE_WEBHOOK_SECRET", "X-Honeybee-Signature") }, only: :create

      def create
        payload = parsed_payload
        return head :ok unless payload

        event_type = payload["event_type"]
        event_id = payload["event_id"]

        LogWebhookEventJob.perform_later(
          event_type: event_type,
          source: "honeybee",
          payload: payload,
          correlation_id: event_id
        )

        if event_id.present? && WebhookIdempotencyService.already_processed?("honeybee", event_id)
          return render json: { status: "already_processed" }, status: :ok
        end

        ProcessHoneybeeWebhookJob.perform_later(payload)

        render json: { status: "accepted" }, status: :ok
      end
    end
  end
end
