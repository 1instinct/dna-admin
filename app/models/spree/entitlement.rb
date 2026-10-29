module Spree
  # What a user is allowed to use (e.g. "pro"), derived from verified store
  # transactions by EntitlementResolver. Never written by clients.
  class Entitlement < Spree::Base
    belongs_to :user, class_name: Spree.user_class.to_s
    belongs_to :iap_transaction, class_name: 'Spree::IapTransaction', optional: true

    validates :key, presence: true, uniqueness: { scope: :user_id }

    scope :current, ->(at = Time.current) { where(active: true).where('expires_at IS NULL OR expires_at > ?', at) }

    def self.current_for(user, key, at = Time.current)
      return nil unless user

      current(at).find_by(user_id: user.id, key: key)
    end

    def current?(at = Time.current)
      active && (expires_at.nil? || expires_at > at)
    end
  end
end
