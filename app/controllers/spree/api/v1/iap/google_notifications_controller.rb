module Spree
  module Api
    module V1
      module Iap
        # POST /api/v1/iap/google/notifications  Pub/Sub push of Play RTDN.
        # If GOOGLE_PLAY_RTDN_TOKEN is set, the push URL must carry ?token=<it>.
        # Messages are only triggers; state is re-read from the Play API.
        class GoogleNotificationsController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication

          before_action :check_push_token

          def create
            envelope = params.permit(message: %i[data messageId message_id publishTime publish_time]).to_h
            result = ::Iap::GoogleNotificationHandler.new.handle(envelope)
            render json: { status: result.outcome == :ignored ? 'ignored' : 'ok' }
          rescue ::Iap::Error => e
            status = e.http_status == 503 ? :service_unavailable : :bad_request
            render json: { error: e.code.to_s }, status: status
          end

          private

          def check_push_token
            expected = ::Iap.config.google_rtdn_token
            return if expected.blank?
            return if ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, expected)

            render json: { error: 'unauthorized' }, status: :unauthorized
          end
        end
      end
    end
  end
end
