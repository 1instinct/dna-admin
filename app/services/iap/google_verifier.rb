module Iap
  # Reads a Google Play purchase from the Play Developer API (the source of
  # truth; the device's purchase JSON is only a pointer) and maps it to a
  # VerifiedTransaction. The purchase token is the transaction id.
  class GoogleVerifier
    SUBSCRIPTION_STATES = {
      'SUBSCRIPTION_STATE_ACTIVE' => 'active',
      'SUBSCRIPTION_STATE_CANCELED' => 'active', # cancelled renewal: access until expiry
      'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' => 'grace',
      'SUBSCRIPTION_STATE_ON_HOLD' => 'billing_retry',
      'SUBSCRIPTION_STATE_PAUSED' => 'expired',
      'SUBSCRIPTION_STATE_EXPIRED' => 'expired',
      'SUBSCRIPTION_STATE_PENDING' => 'pending',
      'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED' => 'expired'
    }.freeze

    PRODUCT_STATES = { 0 => 'active', 1 => 'revoked', 2 => 'pending' }.freeze

    def initialize(client: GoogleClient.new, config: Iap.config)
      @client = client
      @config = config
    end

    def verify_subscription(token)
      json = @client.subscription(token)
      items = Array(json['lineItems'])
      expires_at = items.map { |i| parse_time(i['expiryTime']) }.compact.max
      status = SUBSCRIPTION_STATES.fetch(json['subscriptionState'], 'expired')
      status = 'expired' if status == 'active' && expires_at && expires_at <= Time.current
      price = items.map { |i| i.dig('autoRenewingPlan', 'recurringPrice') }.compact.first

      VerifiedTransaction.new(
        platform: 'google',
        transaction_id: token,
        original_transaction_id: token,
        product_id: items.first&.dig('productId'),
        bundle_id: @config.google_package,
        kind: 'subscription',
        environment: environment!(json.key?('testPurchase')),
        status: status,
        purchased_at: parse_time(json['startTime']),
        expires_at: expires_at,
        grace_expires_at: status == 'grace' ? expires_at : nil,
        auto_renew: items.any? { |i| i.dig('autoRenewingPlan', 'autoRenewEnabled') },
        price: price ? money(price) : nil,
        currency: price&.dig('currencyCode'),
        order_id: json['latestOrderId'],
        acknowledged: json['acknowledgementState'] == 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
        linked_purchase_token: json['linkedPurchaseToken'],
        signed_payload: nil,
        payload: json,
        account_token: json.dig('externalAccountIdentifiers', 'obfuscatedExternalAccountId').presence&.downcase
      )
    end

    def verify_product(sku, token, kind: 'non_consumable')
      json = @client.product(sku, token)
      VerifiedTransaction.new(
        platform: 'google',
        transaction_id: token,
        original_transaction_id: token,
        product_id: json['productId'].presence || sku,
        bundle_id: @config.google_package,
        kind: kind,
        environment: environment!(json['purchaseType'].to_s == '0'),
        status: PRODUCT_STATES.fetch(json['purchaseState'].to_i, 'pending'),
        purchased_at: json['purchaseTimeMillis'].present? ? Time.zone.at(json['purchaseTimeMillis'].to_i / 1000.0) : nil,
        expires_at: nil,
        order_id: json['orderId'],
        acknowledged: json['acknowledgementState'].to_i == 1,
        signed_payload: nil,
        payload: json,
        account_token: json['obfuscatedExternalAccountId'].presence&.downcase
      )
    end

    private

    # License-tester / test purchases count as sandbox and obey IAP_ALLOW_SANDBOX.
    def environment!(test_purchase)
      return 'production' unless test_purchase
      raise Iap::Error.new(:wrong_environment, 'test purchases are not accepted') unless @config.allow_sandbox

      'sandbox'
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value) : nil
    end

    def money(price)
      BigDecimal(price['units'].to_s.presence || '0') + BigDecimal(price['nanos'].to_i) / 1_000_000_000
    end
  end
end
