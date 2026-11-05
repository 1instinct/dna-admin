require 'securerandom'

module Spree
  # A stable per-user UUID the app passes to the store at purchase time
  # (StoreKit appAccountToken / Play obfuscatedAccountId). A verified purchase
  # carrying it belongs to that user, whoever posts it first.
  class IapAccountToken < Spree::Base
    belongs_to :user, class_name: Spree.user_class.to_s

    validates :token, presence: true, uniqueness: true
    validates :user_id, uniqueness: true

    def self.for(user)
      find_or_create_by!(user_id: user.id) { |t| t.token = SecureRandom.uuid }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      find_by!(user_id: user.id)
    end

    def self.owner_id(token)
      return nil if token.blank?

      where(token: token.to_s.downcase).pick(:user_id)
    end
  end
end
