module Iap
  # Verifies a purchase sent by the app and stores it against the user, or
  # updates a transaction from a store notification. Idempotent on
  # (platform, transaction id).
  #
  # Ownership: a purchase carrying an account token (appAccountToken /
  # obfuscatedExternalAccountId) belongs to that token's user; otherwise to the
  # first account that posted any transaction of the same subscription. Anyone
  # else gets account_token_mismatch / already_owned_by_other_user and nothing.
  #
  # Ordering: store data signed before the newest data already applied is
  # stale and never changes state. A refund or revocation is cleared only by an
  # explicit reversal (Apple REFUND_REVERSED).
  class Recorder
    GOOGLE_TYPE_HINTS = {
      'subs' => 'subscription', 'subscription' => 'subscription',
      'inapp' => 'non_consumable', 'non_consumable' => 'non_consumable', 'consumable' => 'consumable'
    }.freeze
    REVOKED_STATUSES = %w[refunded revoked].freeze

    def initialize(apple_verifier: AppleVerifier.new, apple_client: AppleClient.new,
                   google_client: GoogleClient.new, google_verifier: nil, config: Iap.config)
      @apple_verifier = apple_verifier
      @apple_client = apple_client
      @google_client = google_client
      @google_verifier = google_verifier || GoogleVerifier.new(client: google_client, config: config)
      @config = config
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

    # Creates or updates the transaction. user is nil for store notifications.
    #   status_override:   state stated by a store notification
    #   clears_revocation: the notification reverses a refund/revocation
    #   unverified:        device-only data that may not grant (see record_apple)
    def upsert(verified, user: nil, status_override: nil, authoritative: true, clears_revocation: false, unverified: false)
      attempts = 0
      begin
        txn, displaced_user_ids = Spree::IapTransaction.transaction do
          write(verified, user, status_override, authoritative, clears_revocation, unverified)
        end
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 2
        raise
      end
      EntitlementResolver.refresh(txn.user) if txn.user
      Spree.user_class.where(id: displaced_user_ids).find_each { |u| EntitlementResolver.refresh(u) }
      txn
    end

    # Store-side revocation (e.g. a Google voided purchase confirmed by the API).
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
      unless @apple_client.configured?
        # A device JWS proves a purchase happened, not that it still stands (it
        # may predate a refund). Where the store API is required, record it
        # without granting until a store notification or API read confirms it.
        return upsert(verified, user: user, authoritative: false, unverified: @config.require_apple_api)
      end

      fresh = @apple_verifier.verify(@apple_client.transaction_info(verified.transaction_id, environment: verified.environment))
      raise Iap::Error.new(:invalid_purchase, 'transaction mismatch') unless fresh.transaction_id == verified.transaction_id

      upsert(fresh, user: user)
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

    def write(verified, user, status_override, authoritative, clears_revocation, unverified)
      original = original_id_for(verified)
      # Serialize every write for one subscription (all its transaction ids and
      # linked purchase tokens) so two accounts cannot race two of its ids.
      advisory_lock("iap:#{verified.platform}:#{original}")

      txn = Spree::IapTransaction.lock.find_or_initialize_by(platform: verified.platform, transaction_id: verified.transaction_id)
      original = txn.original_transaction_id if txn.persisted?

      token_owner_id = Spree::IapAccountToken.owner_id(verified.account_token)
      if user && verified.account_token.present? && token_owner_id != user.id
        raise Iap::Error.new(:account_token_mismatch, 'this purchase was made by another account')
      end

      owner_id = token_owner_id || txn.user_id || owner_of(verified.platform, original)
      if user && owner_id && owner_id != user.id
        raise Iap::Error.new(:already_owned_by_other_user, 'this purchase belongs to another account')
      end

      stale = txn.persisted? && (unverified || older?(verified.signed_at, txn.store_signed_at))
      apply_state(txn, verified, original, status_override, authoritative, clears_revocation, unverified) unless stale
      txn.user_id = owner_id || user&.id || txn.user_id
      txn.save!

      supersede_linked(verified, txn) unless stale
      displaced_user_ids = []
      if txn.user_id
        siblings = Spree::IapTransaction.where(platform: txn.platform, original_transaction_id: original)
        # Unowned siblings join the owner; with an account token, siblings held
        # by another account move to the token's owner.
        siblings = token_owner_id ? siblings.where.not(user_id: txn.user_id).or(siblings.where(user_id: nil)) : siblings.where(user_id: nil)
        displaced_user_ids = siblings.where.not(user_id: nil).distinct.pluck(:user_id)
        siblings.update_all(user_id: txn.user_id, updated_at: Time.current)
      end
      [txn, displaced_user_ids]
    end

    def apply_state(txn, verified, original, status_override, authoritative, clears_revocation, unverified)
      previous = txn.persisted? ? txn.status : nil
      attrs = verified.to_attributes.merge(original_transaction_id: original)
      attrs.delete(:auto_renew) if attrs[:auto_renew].nil?
      txn.assign_attributes(attrs)
      txn.grace_expires_at = verified.grace_expires_at if verified.grace_expires_at
      # Unverified device data must not make a later-arriving store notification look stale.
      txn.store_signed_at = verified.signed_at if verified.signed_at && !unverified
      txn.account_token = verified.account_token if verified.account_token.present?
      txn.iap_product = Spree::IapProduct.find_by(platform: txn.platform, product_id: txn.product_id) || txn.iap_product
      txn.status = unverified ? 'unverified' : resolve_status(previous, txn, verified.status, status_override, authoritative, clears_revocation)
      txn.verified_at = Time.current
    end

    def older?(incoming, current)
      incoming && current && incoming < current
    end

    def advisory_lock(key)
      Spree::IapTransaction.connection.execute(
        Spree::IapTransaction.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', key])
      )
    end

    # Google upgrades/resubscribes carry linkedPurchaseToken: the new token
    # continues the old purchase (same owner, same original id).
    def original_id_for(verified)
      if verified.linked_purchase_token.present?
        linked = Spree::IapTransaction.find_by(platform: verified.platform, transaction_id: verified.linked_purchase_token)
        return linked.original_transaction_id if linked
      end
      existing = Spree::IapTransaction.find_by(platform: verified.platform, transaction_id: verified.transaction_id)
      existing ? existing.original_transaction_id : verified.original_transaction_id
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

    def resolve_status(previous, txn, derived, override, authoritative, clears_revocation)
      return 'revoked' if txn.admin_revoked_at
      return override if REVOKED_STATUSES.include?(override)
      if REVOKED_STATUSES.include?(previous)
        return previous unless clears_revocation

        return override || derived
      end
      return override if override
      return derived if previous.nil?
      # Transaction data cannot express grace/billing retry; a lapsed period
      # does not erase a state a notification established.
      return previous if %w[grace billing_retry].include?(previous) && derived == 'expired'

      derived
    end
  end
end
