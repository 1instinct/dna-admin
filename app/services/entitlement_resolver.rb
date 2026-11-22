# Derives Spree::Entitlement rows from a user's verified IAP transactions.
# The only writer of entitlements: a user has key K while at least one of
# their transactions for a product mapped to K is active (or in grace) and
# unexpired.
class EntitlementResolver
  def self.refresh(user, at: Time.current)
    new(user, at).refresh
  end

  def initialize(user, at)
    @user = user
    @at = at
  end

  def refresh
    return [] unless @user

    Spree::Entitlement.transaction do
      # Lock before reading: a concurrent refresh must not act on transactions
      # it read before another writer (e.g. a refund) committed.
      lock_user
      transactions = Spree::IapTransaction.where(user_id: @user.id).includes(:iap_product).to_a
                                          .select(&:entitlement_key)
      revoked_chains = admin_revoked_chains(transactions)
      transactions.reject! { |t| revoked_chains.include?([t.platform, t.original_transaction_id]) }
      keys = (transactions.map(&:entitlement_key) + Spree::Entitlement.where(user_id: @user.id).pluck(:key)).uniq

      keys.each { |key| apply(key, transactions.select { |t| t.entitlement_key == key }) }
    end
    Spree::Entitlement.where(user_id: @user.id).order(:key).to_a
  end

  private

  def lock_user
    Spree::Entitlement.connection.execute(
      Spree::Entitlement.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', "iap:entitlements:#{@user.id}"])
    )
  end

  # Subscriptions (platform + original id) an admin revoked any transaction
  # of: none of their transactions grant.
  def admin_revoked_chains(transactions)
    return Set.new if transactions.empty?

    Spree::IapTransaction.where.not(admin_revoked_at: nil)
                         .where(original_transaction_id: transactions.map(&:original_transaction_id).uniq)
                         .distinct.pluck(:platform, :original_transaction_id).to_set
  end

  def apply(key, transactions)
    entitlement = Spree::Entitlement.lock.find_or_initialize_by(user_id: @user.id, key: key)
    granting = transactions.select { |t| t.grants_access?(@at) }

    if granting.any?
      endless = granting.any? { |t| t.access_ends_at.nil? }
      source = granting.max_by { |t| [t.access_ends_at || Time.zone.at(2**40), t.purchased_at || Time.zone.at(0)] }
      entitlement.assign_attributes(
        active: true,
        iap_transaction: source,
        starts_at: granting.map(&:purchased_at).compact.min,
        expires_at: endless ? nil : granting.map(&:access_ends_at).max
      )
    else
      entitlement.active = false
    end
    entitlement.save! if entitlement.new_record? || entitlement.changed?
  end
end
