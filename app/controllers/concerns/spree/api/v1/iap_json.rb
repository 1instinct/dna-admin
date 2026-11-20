module Spree
  module Api
    module V1
      # JSON shapes for IAP endpoints. Signed payloads are never echoed.
      module IapJson
        private

        def iap_transaction_json(txn)
          {
            id: txn.id,
            platform: txn.platform,
            product_id: txn.product_id,
            transaction_id: txn.transaction_id,
            original_transaction_id: txn.original_transaction_id,
            status: txn.effective_status,
            environment: txn.environment,
            entitlement: txn.entitlement_key,
            auto_renew: txn.auto_renew,
            purchased_at: txn.purchased_at&.iso8601,
            expires_at: txn.expires_at&.iso8601,
            revoked_at: (txn.revoked_at || txn.admin_revoked_at)&.iso8601,
            verified_at: txn.verified_at&.iso8601
          }
        end

        def entitlement_json(entitlement)
          {
            key: entitlement.key,
            active: entitlement.current?,
            starts_at: entitlement.starts_at&.iso8601,
            expires_at: entitlement.expires_at&.iso8601,
            transaction_id: entitlement.iap_transaction&.transaction_id,
            platform: entitlement.iap_transaction&.platform
          }
        end

        def entitlements_json(user)
          Spree::Entitlement.where(user_id: user.id).includes(:iap_transaction).order(:key).map { |e| entitlement_json(e) }
        end

        def render_iap_error(error)
          render json: { error: error.code.to_s, message: error.message }, status: error.http_status
        end
      end
    end
  end
end
