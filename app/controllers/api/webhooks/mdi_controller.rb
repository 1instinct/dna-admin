module Api
  module Webhooks
    class MdiController < BaseController
      before_action -> { verify_hmac!("MDI_WEBHOOK_SECRET", "X-MDI-Signature") }, only: :create

      def create
        payload = parsed_payload
        return head :ok unless payload

        event_type = payload["event_type"]
        encounter_id = payload["encounter_id"]

        LogWebhookEventJob.perform_later(
          event_type: event_type,
          source: "mdi",
          payload: payload,
          correlation_id: encounter_id
        )

        return head :ok if encounter_id.blank?

        event_id = "#{encounter_id}:#{event_type}"
        if WebhookIdempotencyService.already_processed?("mdi", event_id)
          return render json: { status: "already_processed" }, status: :ok
        end

        ProcessMdiWebhookJob.perform_later(payload)

        render json: { status: "accepted" }, status: :ok
      end

      def show
        client = MdiClient.new
        result = client.fetch_encounter(params[:encounter_id])
        render json: result
      rescue Faraday::ResourceNotFound
        head :not_found
      end
    end
  end
end
