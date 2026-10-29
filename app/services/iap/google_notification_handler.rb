require 'base64'

module Iap
  # Google Play Real-time Developer Notifications (Pub/Sub push). The message
  # is only a trigger: purchase state is always re-read from the Play
  # Developer API. Redelivered messages (same messageId) are no-ops once
  # processed; a Play outage raises store_unreachable so Pub/Sub retries.
  class GoogleNotificationHandler
    SUBSCRIPTION_TYPES = {
      1 => 'SUBSCRIPTION_RECOVERED', 2 => 'SUBSCRIPTION_RENEWED', 3 => 'SUBSCRIPTION_CANCELED',
      4 => 'SUBSCRIPTION_PURCHASED', 5 => 'SUBSCRIPTION_ON_HOLD', 6 => 'SUBSCRIPTION_IN_GRACE_PERIOD',
      7 => 'SUBSCRIPTION_RESTARTED', 8 => 'SUBSCRIPTION_PRICE_CHANGE_CONFIRMED', 9 => 'SUBSCRIPTION_DEFERRED',
      10 => 'SUBSCRIPTION_PAUSED', 11 => 'SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED', 12 => 'SUBSCRIPTION_REVOKED',
      13 => 'SUBSCRIPTION_EXPIRED', 19 => 'SUBSCRIPTION_PRICE_CHANGE_UPDATED', 20 => 'SUBSCRIPTION_PENDING_PURCHASE_CANCELED'
    }.freeze
    ONE_TIME_TYPES = { 1 => 'ONE_TIME_PRODUCT_PURCHASED', 2 => 'ONE_TIME_PRODUCT_CANCELED' }.freeze

    Result = Struct.new(:notification, :outcome)

    def initialize(recorder: Recorder.new, verifier: nil, client: GoogleClient.new, config: Iap.config)
      @recorder = recorder
      @client = client
      @verifier = verifier || GoogleVerifier.new(client: client, config: config)
      @config = config
    end

    # Call only after the push request is authenticated (GooglePushAuthenticator).
    def handle(envelope)
      message = envelope.is_a?(Hash) ? (envelope['message'] || {}) : {}
      data = decode(message['data'])
      id = (message['messageId'] || message['message_id']).presence || raise(Iap::Error.new(:invalid_payload, 'messageId missing'))

      # Messages for another app leave no row behind, so they can never
      # occupy (and suppress) a real message id.
      return Result.new(nil, :ignored) if @config.google_package.blank? || data['packageName'] != @config.google_package

      notification = Spree::IapNotification.find_or_initialize_by(platform: 'google', notification_id: id.to_s)
      return Result.new(notification, :duplicate) if notification.processed_at

      type, subtype = describe(data)
      notification.assign_attributes(notification_type: type, subtype: subtype, payload: data)
      notification.save!
      @note = nil
      notification.iap_transaction = process(data)
      notification.update!(processed_at: Time.current, error: @note)
      Result.new(notification, :processed)
    rescue Iap::Error => e
      if e.code == :wrong_environment && notification&.persisted?
        # Test purchase while sandbox is disallowed: acknowledge, change nothing.
        notification.update!(processed_at: Time.current, error: 'ignored: sandbox purchase')
        return Result.new(notification, :ignored)
      end
      notification.update_columns(error: e.code.to_s, updated_at: Time.current) if notification&.persisted?
      raise
    end

    private

    def decode(raw)
      raise Iap::Error.new(:invalid_payload, 'message.data missing') unless raw.is_a?(String) && raw.present?

      parsed = JSON.parse(Base64.strict_decode64(raw))
      raise Iap::Error.new(:invalid_payload, 'message.data is not an object') unless parsed.is_a?(Hash)

      parsed
    rescue ArgumentError, JSON::ParserError
      raise Iap::Error.new(:invalid_payload, 'message.data is not base64 JSON')
    end

    def describe(data)
      if (n = data['subscriptionNotification'])
        [SUBSCRIPTION_TYPES.fetch(n['notificationType'].to_i, "SUBSCRIPTION_#{n['notificationType']}"), n['subscriptionId']]
      elsif (n = data['oneTimeProductNotification'])
        [ONE_TIME_TYPES.fetch(n['notificationType'].to_i, "ONE_TIME_#{n['notificationType']}"), n['sku']]
      elsif (n = data['voidedPurchaseNotification'])
        ['VOIDED_PURCHASE', "refundType=#{n['refundType']}"]
      elsif data.key?('testNotification')
        ['TEST', nil]
      else
        ['UNKNOWN', nil]
      end
    end

    # State always comes from the Play Developer API, never from the message.
    def process(data)
      if (n = data['subscriptionNotification'])
        verified = @verifier.verify_subscription(n['purchaseToken'].to_s)
        txn = @recorder.upsert(verified)
        @recorder.acknowledge_google(txn, verified)
      elsif (n = data['oneTimeProductNotification'])
        sku = n['sku'].to_s
        kind = Spree::IapProduct.find_by(platform: 'google', product_id: sku)&.kind || 'non_consumable'
        verified = @verifier.verify_product(sku, n['purchaseToken'].to_s, kind: kind)
        txn = @recorder.upsert(verified)
        @recorder.acknowledge_google(txn, verified)
      elsif (n = data['voidedPurchaseNotification'])
        process_void(data, n)
      end
    end

    VOIDED_LOOKBACK = 2.days
    VOIDED_MAX_PAGES = 10

    # Confirms the void with purchases.voidedpurchases before refunding.
    def process_void(data, n)
      token = n['purchaseToken'].to_s
      txn = Spree::IapTransaction.find_by(platform: 'google', transaction_id: token)
      return nil unless txn

      event = data['eventTimeMillis'].present? ? Time.zone.at(data['eventTimeMillis'].to_i / 1000.0) : Time.current
      start = [event - VOIDED_LOOKBACK, 29.days.ago].max
      voided = find_voided(token, start)
      unless voided
        @note = 'void_not_confirmed'
        return txn
      end

      at = voided['voidedTimeMillis'].present? ? Time.zone.at(voided['voidedTimeMillis'].to_i / 1000.0) : event
      @recorder.revoke(txn, status: 'refunded', revoked_at: at, reason: "voided reason=#{voided['voidedReason']}")
    end

    def find_voided(token, start)
      page_token = nil
      VOIDED_MAX_PAGES.times do
        body = @client.voided_purchases(start_time: start, page_token: page_token)
        match = Array(body['voidedPurchases']).find { |v| v['purchaseToken'] == token }
        return match if match

        page_token = body.dig('tokenPagination', 'nextPageToken')
        break if page_token.blank?
      end
      nil
    end
  end
end
