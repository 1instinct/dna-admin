module Iap
  # App Store Server Notifications v2. The notification and the transaction it
  # carries are both verified JWS; the transaction is created or updated
  # (possibly before the app has posted it) and the notification is kept as
  # history. Redelivered notifications (same notificationUUID) are no-ops.
  class AppleNotificationHandler
    # Types that state the subscription's new condition outright.
    STATUS_OVERRIDES = {
      'REFUND' => 'refunded',
      'REVOKE' => 'revoked',
      'EXPIRED' => 'expired',
      'GRACE_PERIOD_EXPIRED' => 'expired'
    }.freeze
    # Types after which the transaction's own data is the truth again.
    FRESH_TYPES = %w[SUBSCRIBED DID_RENEW REFUND_REVERSED OFFER_REDEEMED RENEWAL_EXTENDED ONE_TIME_CHARGE].freeze

    def initialize(verifier: AppleVerifier.new, recorder: Recorder.new)
      @verifier = verifier
      @recorder = recorder
    end

    def handle(signed_payload)
      raise Iap::Error.new(:invalid_payload, 'signedPayload is required') unless signed_payload.is_a?(String) && signed_payload.present?

      payload = @verifier.verify_notification(signed_payload)
      uuid = payload['notificationUUID'].presence || raise(Iap::Error.new(:invalid_payload, 'notificationUUID missing'))
      notification = Spree::IapNotification.find_or_initialize_by(platform: 'apple', notification_id: uuid)
      return notification if notification.processed_at

      data = payload['data'] || {}
      notification.assign_attributes(notification_type: payload['notificationType'], subtype: payload['subtype'],
                                     environment: data['environment']&.downcase, signed_payload: signed_payload,
                                     payload: payload)
      notification.save!

      if data['signedTransactionInfo'].present?
        verified = @verifier.verify(data['signedTransactionInfo'])
        apply_renewal_info(verified, data['signedRenewalInfo'])
        notification.iap_transaction = @recorder.upsert(verified, status_override: status_for(payload, verified))
      end
      notification.update!(processed_at: Time.current, error: nil)
      notification
    rescue Iap::Error => e
      notification.update_columns(error: e.code.to_s, updated_at: Time.current) if notification&.persisted?
      raise
    end

    private

    def apply_renewal_info(verified, signed_renewal)
      return if signed_renewal.blank?

      renewal = @verifier.decode(signed_renewal)
      verified.auto_renew = renewal['autoRenewStatus'].to_i == 1 if renewal.key?('autoRenewStatus')
      grace = renewal['gracePeriodExpiresDate']
      verified.grace_expires_at = Time.zone.at(grace.to_i / 1000.0) if grace.present?
    end

    def status_for(payload, verified)
      type = payload['notificationType']
      return payload['subtype'] == 'GRACE_PERIOD' ? 'grace' : 'billing_retry' if type == 'DID_FAIL_TO_RENEW'
      return STATUS_OVERRIDES[type] if STATUS_OVERRIDES.key?(type)
      return verified.status if FRESH_TYPES.include?(type)

      nil
    end
  end
end
