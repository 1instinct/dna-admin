module Spree
  module Api
    module V1
      module Iap
        # POST /api/v1/iap/restore  { purchases: [{ platform, signed_payload | purchase_token + product_id }] }
        # Records each purchase independently and reports a result per item.
        class RestoresController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication
          include Spree::Api::V1::IapJson

          MAX_PURCHASES = 100

          before_action :require_api_user!

          def create
            purchases = Array(params[:purchases])
            if purchases.size > MAX_PURCHASES
              return render_error('too_many_purchases', :unprocessable_entity, "at most #{MAX_PURCHASES} purchases per restore")
            end

            recorder = ::Iap::Recorder.new
            results = purchases.each_with_index.map do |purchase, index|
              item = purchase.respond_to?(:permit) ? purchase.permit(:platform, :signed_payload, :purchase_token, :product_id, :type).to_h : {}
              txn = recorder.record(api_user, item['platform'], item.except('platform'))
              { index: index, status: 'ok', transaction: iap_transaction_json(txn) }
            rescue ::Iap::Error => e
              { index: index, status: 'error', error: e.code.to_s, message: e.message }
            end

            render json: { results: results, entitlements: entitlements_json(api_user) }
          end
        end
      end
    end
  end
end
