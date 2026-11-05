module Spree
  # A server-to-server notification from a store (App Store Server
  # Notifications v2 or Google Play RTDN). Unique per store message id, which
  # makes redelivery idempotent.
  class IapNotification < Spree::Base
    belongs_to :iap_transaction, class_name: 'Spree::IapTransaction', optional: true

    validates :platform, inclusion: { in: Spree::IapProduct::PLATFORMS }
    validates :notification_id, presence: true, uniqueness: { scope: :platform }

    scope :newest_first, -> { order(created_at: :desc) }
  end
end
