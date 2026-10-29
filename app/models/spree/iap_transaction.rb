module Spree
  # One store transaction (Apple transaction id / Google purchase token),
  # verified server-side. The signed payload is kept verbatim for audit.
  class IapTransaction < Spree::Base
    STATUSES = %w[active expired revoked refunded grace billing_retry pending].freeze
    GRANTING_STATUSES = %w[active grace].freeze
    ENVIRONMENTS = %w[production sandbox].freeze

    belongs_to :user, class_name: Spree.user_class.to_s, optional: true
    belongs_to :iap_product, class_name: 'Spree::IapProduct', optional: true
    has_many :iap_notifications, class_name: 'Spree::IapNotification', dependent: :nullify
    has_many :entitlements, class_name: 'Spree::Entitlement', dependent: :nullify
    has_many :audit_logs, class_name: 'Spree::IapAuditLog', dependent: :destroy

    validates :platform, inclusion: { in: Spree::IapProduct::PLATFORMS }
    validates :status, inclusion: { in: STATUSES }
    validates :environment, inclusion: { in: ENVIRONMENTS }
    validates :transaction_id, :original_transaction_id, :product_id, presence: true
    validates :transaction_id, uniqueness: { scope: :platform }

    scope :newest_first, -> { order(created_at: :desc) }

    def entitlement_key
      iap_product&.grants_entitlement? ? iap_product.entitlement : nil
    end

    # When access granted by this transaction ends (nil = never).
    def access_ends_at
      status == 'grace' ? (grace_expires_at || expires_at) : expires_at
    end

    def grants_access?(at = Time.current)
      return false unless GRANTING_STATUSES.include?(status)
      return false if revoked_at || admin_revoked_at

      ends = access_ends_at
      ends.nil? || ends > at
    end

    # Status as of now: a stored "active" whose period has ended reads "expired".
    def effective_status(at = Time.current)
      return 'expired' if GRANTING_STATUSES.include?(status) && access_ends_at && access_ends_at <= at

      status
    end
  end
end
