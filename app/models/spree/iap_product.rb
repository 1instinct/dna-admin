module Spree
  # A store product sold through the App Store or Google Play, mapped to the
  # entitlement key it unlocks (e.g. "pro"). Product ids come from admin data,
  # never from code.
  class IapProduct < Spree::Base
    PLATFORMS = %w[apple google].freeze
    KINDS = %w[subscription non_consumable consumable].freeze

    belongs_to :store, class_name: 'Spree::Store', optional: true
    has_many :iap_transactions, class_name: 'Spree::IapTransaction', dependent: :nullify

    validates :platform, inclusion: { in: PLATFORMS }
    validates :kind, inclusion: { in: KINDS }
    validates :product_id, presence: true, uniqueness: { scope: :platform }

    scope :active, -> { where(active: true) }

    after_save :link_transactions

    def grants_entitlement?
      entitlement.present? && kind != 'consumable'
    end

    private

    # Transactions recorded before the product was catalogued pick it up, and
    # their owners' entitlements are recomputed.
    def link_transactions
      return unless saved_change_to_product_id? || saved_change_to_platform? || saved_change_to_entitlement? || saved_change_to_kind? || saved_change_to_id?

      Spree::IapTransaction.where(platform: platform, product_id: product_id, iap_product_id: nil).update_all(iap_product_id: id)
      user_ids = Spree::IapTransaction.where(iap_product_id: id).where.not(user_id: nil).distinct.pluck(:user_id)
      Spree.user_class.where(id: user_ids).find_each { |user| EntitlementResolver.refresh(user) }
    end
  end
end
