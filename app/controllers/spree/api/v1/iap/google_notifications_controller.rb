module Spree
  module Api
    module V1
      module Iap
        # POST /api/v1/iap/google/notifications  Pub/Sub push of Play RTDN.
        # Requires the Pub/Sub OIDC token (see Iap::GooglePushAuthenticator).
        # Messages are only triggers; state is re-read from the Play API.
        class GoogleNotificationsController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication

          def create
            ::Iap::GooglePushAuthenticator.new.authenticate!(request)
            envelope = params.permit(message: %i[data messageId message_id publishTime publish_time]).to_h
            result = ::Iap::GoogleNotificationHandler.new.handle(envelope)
            render json: { status: result.outcome == :ignored ? 'ignored' : 'ok' }
          rescue ::Iap::Error => e
            status = case e.http_status
                     when 401 then :unauthorized
                     when 503 then :service_unavailable
                     else :bad_request
                     end
            render json: { error: e.code.to_s }, status: status
          end
        end
      end
    end
  end
end
