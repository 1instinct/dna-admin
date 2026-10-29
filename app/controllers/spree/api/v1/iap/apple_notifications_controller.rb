module Spree
  module Api
    module V1
      module Iap
        # POST /api/v1/iap/apple/notifications  App Store Server Notifications v2
        # ({ "signedPayload": "<JWS>" }). Authenticity comes from the JWS chain.
        class AppleNotificationsController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication

          def create
            notification = ::Iap::AppleNotificationHandler.new.handle(params[:signedPayload])
            render json: { status: 'ok', notification_id: notification.notification_id }
          rescue ::Iap::Error => e
            status = e.http_status == 503 ? :service_unavailable : :bad_request
            render json: { error: e.code.to_s }, status: status
          end
        end
      end
    end
  end
end
