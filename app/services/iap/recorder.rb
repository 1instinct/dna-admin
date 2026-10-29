module Iap
  # Verifies a purchase sent by the app and stores it against the user, or
  # updates a transaction from a store notification. Idempotent on
  # (platform, transaction id). A purchase already linked to another user is
  # refused (already_owned_by_other_user) and grants nothing.
  class Recorder
    GOOGLE_TYPE_HINTS = {
      'subs' => 'subscription', 'subscription' => 'subscription',
      'inapp' => 'non_consumable', 'non_consumable' => 'non_consumable', 'consumable' => 'consumable'
    }.freeze

    def initialize(apple_verifier: AppleVerifier.new, apple_client: AppleClient.new,
                   google_client: GoogleClient.new, google_verifier: nil)
      @apple_verifier = apple_verifier
      @apple_client = apple_client
      @google_client = google_client
      @google_verifier = google_verifier || GoogleVerifier.new(client: google_client)
    end

    # payload: apple => { signed_payload: <JWS> }
    #          google => { purchase_token:, product_id:, type: ('subs'|'inapp', only for uncatalogued products) }
    def record(user, platform, payload)
      payload = normalize(payload)
      case platform.to_s
      when 'apple' then record_apple(user, payload)
      when 'google' then record_google(user, payload)
      else raise Iap::Error.new(:invalid_platform)
      end
    end

    # Creates or updates the transaction. user is nil for store notifications;
    # ownership is then inherited from earlier transactions of the same
    # original transaction.
    def upsert(verified, user: nil, status_override: nil, authoritative: true)
      attempts = 0
      begin
        txn = Spree::IapTransaction.transaction { write(verified, user, status_override, authoritative) }
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 2
        raise
      end
      EntitlementResolver.refresh(txn.user) if txn.user
      txn
    end

    # Store-side revocation (e.g. Google voided purchase).
    def revoke(txn, status:, revoked_at:, reason: nil)
      txn.update!(status: status, revoked_at: revoked_at || Time.current, revocation_reason: reason)
      EntitlementResolver.refresh(txn.user) if txn.user
      txn
    end

    # Google requires acknowledgement within 3 days or it refunds. Only done
    # once the purchase belongs to a user and is in a granting state; failures
    # leave acknowledged_at empty so a later post or notification retries.
    def acknowledge_google(txn, verified)
      if verified.acknowledged
        txn.update_column(:acknowledged_at, Time.current) if txn.acknowledged_at.nil?
        return txn
      end
      return txn unless txn.user_id && Spree::IapTransaction::GRANTING_STATUSES.include?(txn.status)

      @google_client.acknowledge(kind: verified.kind, sku: txn.product_id, token: txn.transaction_id)
      txn.update_column(:acknowledged_at, Time.current)
      txn
    rescue Iap::Error => e
      Rails.logger.warn("[iap] Google acknowledge failed for transaction #{txn.id}: #{e.code}")
      txn
    end

    private

    def normalize(payload)
      hash = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload.to_h
      hash.with_indifferent_access
    end

    def record_apple(user, payload)
      jws = payload[:signed_payload]
      raise Iap::Error.new(:invalid_payload, 'signed_payload is required') unless jws.is_a?(String) && jws.present?

      verified = @apple_verifier.verify(jws)
      authoritative = false
      if @apple_client.configured?
        fresh = @apple_verifier.verify(@apple_client.transaction_info(verified.transaction_id, environment: verified.environment))
        raise Iap::Error.new(:invalid_purchase, 'transaction mismatch') unless fresh.transaction_id == verified.transaction_id

        verified = fresh
        authoritative = true
      end
      upsert(verified, user: user, authoritative: authoritative)
    end

    def record_google(user, payload)
      token = payload[:purchase_token]
      sku = payload[:product_id]
      raise Iap::Error.new(:invalid_payload, 'purchase_token and product_id are required') unless token.is_a?(String) && token.present? && sku.present?

      product = Spree::IapProduct.find_by(platform: 'google', product_id: sku)
      kind = product&.kind || GOOGLE_TYPE_HINTS[payload[:type].to_s]
      raise Iap::Error.new(:unknown_product) unless kind

      verified = kind == 'subscription' ? @google_verifier.verify_subscription(token) : @google_verifier.verify_product(sku, token, kind: kind)
      txn = upsert(verified, user: user)
      acknowledge_google(txn, verified)
    end

    def write(verified, user, status_override, authoritative)
      txn = Spree::IapTransaction.lock.find_or_initialize_by(platform: verified.platform, transaction_id: verified.transaction_id)
      original = original_id_for(verified, txn)
      owner_id = txn.user_id || owner_of(verified.platform, original)
      if user && owner_id && owner_id != user.id
        raise Iap::Error.new(:already_owned_by_other_user, 'this purchase belongs to another account')
      end

      previous = txn.persisted? ? txn.status : nil
      attrs = verified.to_attributes.merge(original_transaction_id: original)
      attrs.delete(:auto_renew) if attrs[:auto_renew].nil?
      txn.assign_attributes(attrs)
      txn.grace_expires_at = verified.grace_expires_at if verified.grace_expires_at
      txn.user_id ||= user&.id || owner_id
      txn.iap_product = Spree::IapProduct.find_by(platform: txn.platform, product_id: txn.product_id) || txn.iap_product
      txn.status = resolve_status(previous, txn, verified.status, status_override, authoritative)
      txn.verified_at = Time.current
      txn.save!

      supersede_linked(verified, txn)
      if txn.user_id
        Spree::IapTransaction.where(platform: txn.platform, original_transaction_id: original, user_id: nil)
                             .update_all(user_id: txn.user_id, updated_at: Time.current)
      end
      txn
    end

    # Google upgrades/resubscribes carry linkedPurchaseToken: the new token
    # continues the old purchase (same owner, same original id).
    def original_id_for(verified, txn)
      if verified.linked_purchase_token.present?
        linked = Spree::IapTransaction.find_by(platform: verified.platform, transaction_id: verified.linked_purchase_token)
        return linked.original_transaction_id if linked
      end
      txn.persisted? ? txn.original_transaction_id : verified.original_transaction_id
    end

    def supersede_linked(verified, txn)
      return if verified.linked_purchase_token.blank?

      Spree::IapTransaction.where(platform: txn.platform, transaction_id: verified.linked_purchase_token)
                           .where.not(id: txn.id).where(status: Spree::IapTransaction::GRANTING_STATUSES)
                           .update_all(status: 'expired', updated_at: Time.current)
    end

    def owner_of(platform, original)
      Spree::IapTransaction.where(platform: platform, original_transaction_id: original).where.not(user_id: nil).pick(:user_id)
    end

    # Notifications state what happened (override). Device-supplied data that
    # was not re-read from the store never undoes a refund or revocation, and a
    # lapsed period does not erase a known grace/billing-retry state.
    def resolve_status(previous, txn, derived, override, authoritative)
      return 'revoked' if txn.admin_revoked_at
      return override if override
      return derived if previous.nil?
      return previous if previous == 'refunded' && %w[revoked expired].include?(derived)
      return previous if !authoritative && %w[refunded revoked].include?(previous)
      return previous if %w[grace billing_retry].include?(previous) && derived == 'expired'

      derived
    end
  end
end
