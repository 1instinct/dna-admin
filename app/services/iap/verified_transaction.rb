module Iap
  # A store transaction whose authenticity has been established (Apple JWS
  # chain verified, or read from the Google Play Developer API).
  VerifiedTransaction = Struct.new(
    :platform, :transaction_id, :original_transaction_id, :product_id, :bundle_id, :kind,
    :environment, :status, :purchased_at, :expires_at, :grace_expires_at, :revoked_at,
    :revocation_reason, :auto_renew, :price, :currency, :order_id, :acknowledged,
    :linked_purchase_token, :signed_payload, :payload,
    keyword_init: true
  ) do
    def to_attributes
      {
        platform: platform,
        transaction_id: transaction_id,
        original_transaction_id: original_transaction_id,
        product_id: product_id,
        environment: environment,
        purchased_at: purchased_at,
        expires_at: expires_at,
        revoked_at: revoked_at,
        revocation_reason: revocation_reason,
        auto_renew: auto_renew,
        price: price,
        currency: currency,
        order_id: order_id,
        signed_payload: signed_payload,
        payload: payload || {}
      }
    end
  end
end
