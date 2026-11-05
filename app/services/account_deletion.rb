# Deletes a customer's account at their own request (app-store account deletion).
#
# Deleted:    OAuth access tokens and grants (revoked), the user's own content (favorites,
#             follows, messages, live stream likes, avatar), the public profile and its photo,
#             blocks either way, reports about the user's profile, saved addresses no order
#             uses, saved payment sources no remaining payment uses, and open carts that never
#             took a payment. Sources a remaining payment uses are detached from the user instead.
# Anonymized: the user row (email -> deleted-<id>@invalid, login/profile/tokens/IPs cleared,
#             password scrambled), then soft-deleted (acts_as_paranoid). The original email can
#             sign up again.
# Retained:   orders that completed or took a payment, with their addresses, payments and
#             shipments (email anonymized), store credit and loyalty points, for accounting;
#             reports the user filed, with reporter_id and the free-text details cleared
#             (moderation record: reason and target snapshot stay).
#
# Refused (AccountDeletion::Refused, with a message for the user) for admin accounts.
class AccountDeletion
  class Refused < StandardError; end

  ADMIN_REFUSAL = "Admin accounts can't be deleted from the app. Contact support to close this account.".freeze

  # Credentials, tokens and tracking data on the user row.
  CREDENTIAL_COLUMNS = %w[
    spree_api_key remember_token remember_created_at persistence_token perishable_token
    reset_password_token reset_password_sent_at authentication_token unlock_token
    confirmation_token unconfirmed_email current_sign_in_ip last_sign_in_ip
  ].freeze

  # Profile columns, cleared when the table has them. Apps that add their own profile columns
  # to spree_users extend this list.
  PROFILE_COLUMNS = %w[
    login first_name last_name firstname lastname name display_name username phone bio
    avatar_url banner_url website city birthday
  ].freeze

  # Payment states that mean money may have moved (a void had an authorization at the gateway);
  # an open order with one of these is retained.
  MONEY_PAYMENT_STATES = %w[processing pending completed void].freeze

  def self.call(user)
    new(user).call
  end

  attr_reader :user, :now

  def initialize(user, now: Time.current)
    @user = user
    @now = now
  end

  def call
    raise Refused, ADMIN_REFUSAL if user.admin?

    ActiveRecord::Base.transaction do
      user.lock!
      revoke_oauth
      delete_content
      remove_open_carts
      anonymize_orders
      remove_addresses
      remove_payment_sources
      anonymize_and_soft_delete_user
    end

    purge_avatars
    Rails.logger.info("[account_deletion] user_id=#{user.id} deleted_at=#{now.utc.iso8601}")
    true
  end

  def anonymized_email
    "deleted-#{user.id}@invalid"
  end

  private

  def revoke_oauth
    [Doorkeeper.config.access_token_model, Doorkeeper.config.access_grant_model].each do |model|
      model.where(resource_owner_id: user.id, revoked_at: nil).update_all(revoked_at: now)
    end
  end

  def delete_content
    Favorite.where(user_id: user.id).delete_all
    UserFollow.where(follower_id: user.id).or(UserFollow.where(following_id: user.id)).delete_all
    LiveStreamLike.where(user_id: user.id).delete_all
    Message.where(sender: user).or(Message.where(receiver: user)).delete_all
    delete_profile_data
    # In-app purchase receipts are payment records: when that module lands, keep them for
    # accounting and detach or anonymize them here rather than deleting.
  end

  # Profile row (its photo is purged after commit), blocks either way, reports about the profile.
  # Reports the user filed stay for moderation, without the reporter or their free text.
  def delete_profile_data
    Spree::UserBlock.involving(user).delete_all
    Spree::ProfileRateCounter.where(user_id: user.id).delete_all
    Spree::ContentReport.where(reporter_id: user.id).update_all(reporter_id: nil, details: nil, updated_at: now)
    Spree::UserProfile.where(user_id: user.id).find_each do |profile|
      Spree::ContentReport.about_profile(profile).delete_all
      if profile.avatar.attached?
        avatar_blobs << profile.avatar.blob
        profile.avatar.detach
      end
      profile.destroy!
    end
  end

  def avatar_blobs
    @avatar_blobs ||= []
  end

  def remove_open_carts
    Spree::Order.incomplete.where(user_id: user.id).includes(:payments).find_each do |order|
      next if order.payments.any? { |payment| MONEY_PAYMENT_STATES.include?(payment.state) }

      # Spree reuses the user's saved address on new carts, so a cart may share an address with
      # a retained order; Order's `dependent: :destroy` on its addresses would then fail. Detach
      # them first and remove the ones nothing else uses.
      address_ids = [order.bill_address_id, order.ship_address_id].compact.uniq
      order.update_columns(bill_address_id: nil, ship_address_id: nil)
      order.destroy!
      Spree::Address.where(id: address_ids).find_each(&:destroy)
    end
  end

  def anonymize_orders
    Spree::Order.where(user_id: user.id).update_all(email: anonymized_email, last_ip_address: nil, updated_at: now)
  end

  # Spree::Address#destroy hard-deletes an address no order or shipment uses and soft-deletes
  # one that is still referenced; referenced ones also leave the user's address book.
  def remove_addresses
    user.update_columns(bill_address_id: nil, ship_address_id: nil)
    Spree::Address.where(user_id: user.id).find_each do |address|
      address.destroy
      Spree::Address.where(id: address.id).update_all(user_id: nil)
    end
  end

  def remove_payment_sources
    remove_credit_cards
    remove_checks
  end

  # Cleared on every saved card: the cardholder.
  CARD_HOLDER_COLUMNS = %w[name].freeze
  # Also cleared on cards no payment uses, which are then soft-deleted (acts_as_paranoid).
  CARD_DETAIL_COLUMNS = %w[last_digits gateway_customer_profile_id gateway_payment_profile_id].freeze

  # Spree::Payment's polymorphic source doesn't see soft-deleted cards, so a card that a remaining
  # payment uses is only detached from the user and keeps what the gateway needs to capture, void
  # or refund (profile ids, last digits, type, expiry). Cards nothing uses are cleared and
  # soft-deleted.
  def remove_credit_cards
    cards = Spree::CreditCard.where(user_id: user.id)
    used_ids = Spree::Payment.where(source_type: Spree::CreditCard.name, source_id: cards.select(:id)).pluck(:source_id)
    detach = (CARD_HOLDER_COLUMNS & Spree::CreditCard.column_names).index_with(nil).
             merge('user_id' => nil, 'default' => false, 'updated_at' => now)
    cards.where(id: used_ids).update_all(detach)
    cleared = detach.merge((CARD_DETAIL_COLUMNS & Spree::CreditCard.column_names).index_with(nil))
    cards.where.not(id: used_ids).find_each do |card|
      card.update_columns(cleared)
      card.destroy!
    end
  end

  CHECK_DETAIL_COLUMNS = %w[
    account_holder_name account_number routing_number last_digits
    gateway_customer_profile_id gateway_payment_profile_id
  ].freeze

  # Spree::Check (spree_gateway) is not paranoid and retained payments may use one as their
  # source, so checks are soft-deleted by hand; account details are cleared only on checks no
  # remaining payment uses.
  def remove_checks
    check_class = 'Spree::Check'.safe_constantize
    return unless check_class

    checks = check_class.where(user_id: user.id)
    used_ids = Spree::Payment.where(source_type: check_class.name, source_id: checks.select(:id)).pluck(:source_id)
    details = (CHECK_DETAIL_COLUMNS & check_class.column_names).index_with(nil)
    checks.where.not(id: used_ids).update_all(details) if details.any?
    soft_delete = { user_id: nil, updated_at: now }
    soft_delete[:deleted_at] = now if check_class.column_names.include?('deleted_at')
    checks.update_all(soft_delete)
  end

  def anonymize_and_soft_delete_user
    columns = user.class.column_names
    attrs = {}
    (CREDENTIAL_COLUMNS + PROFILE_COLUMNS).each do |name|
      next unless columns.include?(name)

      attrs[name] = user.class.columns_hash[name].null ? nil : user.class.column_defaults[name]
    end
    attrs['email'] = anonymized_email
    attrs['encrypted_password'] = SecureRandom.hex(64) if columns.include?('encrypted_password')
    attrs['password_salt'] = SecureRandom.hex(20) if columns.include?('password_salt')
    attrs['deleted_at'] = now
    attrs['updated_at'] = now
    user.update_columns(attrs)
  end

  # Inline, after commit: queued jobs don't survive a dyno restart, and the account is already
  # deleted by now, so a storage failure is logged rather than raised.
  def purge_avatars
    avatar_blobs << user.avatar.blob if user.respond_to?(:avatar) && user.avatar.respond_to?(:attached?) && user.avatar.attached?
    avatar_blobs.each do |blob|
      blob.purge
    rescue StandardError => e
      # The blob row may already be gone, so the key is the only trace of the orphaned file.
      Rails.logger.error("[account_deletion] user_id=#{user.id} blob_key=#{blob.key} avatar purge failed: #{e.class}")
    end
  end
end
