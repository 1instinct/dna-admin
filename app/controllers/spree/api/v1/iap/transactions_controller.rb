module Spree
  module Api
    module V1
      module Iap
        # POST /api/v1/iap/transactions   verify + record a purchase for the caller
        # GET  /api/v1/iap/transactions   the caller's purchases
        # GET  /api/v1/iap/transactions/:id
        class TransactionsController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication
          include Spree::Api::V1::IapJson

          before_action :require_api_user!

          def index
            transactions = Spree::IapTransaction.where(user_id: api_user.id).includes(:iap_product).newest_first.limit(200)
            render json: { transactions: transactions.map { |t| iap_transaction_json(t) } }
          end

          def show
            txn = Spree::IapTransaction.where(user_id: api_user.id).find(params[:id])
            render json: { transaction: iap_transaction_json(txn) }
          end

          def create
            txn = ::Iap::Recorder.new.record(api_user, params[:platform], purchase_params)
            render json: { transaction: iap_transaction_json(txn), entitlements: entitlements_json(api_user) }
          rescue ::Iap::Error => e
            render_iap_error(e)
          end

          private

          def purchase_params
            params.permit(:signed_payload, :purchase_token, :product_id, :type).to_h
          end
        end
      end
    end
  end
end
