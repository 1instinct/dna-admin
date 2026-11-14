# Affiliate attribution on orders: the affiliate account the order came through (set once, while
# the order is incomplete, by Affiliates::Attribution) and the commission it earned.
# Loaded by the to_prepare decorator glob.
module Spree
  module OrderAffiliateDecorator
    def self.prepended(base)
      base.belongs_to :affiliate_account, class_name: 'AffiliateAccount', optional: true
      base.has_one :affiliate_commission, class_name: 'AffiliateCommission', foreign_key: :order_id, inverse_of: :order
    end
  end
end

Spree::Order.prepend(Spree::OrderAffiliateDecorator) unless Spree::Order.ancestors.include?(Spree::OrderAffiliateDecorator)
