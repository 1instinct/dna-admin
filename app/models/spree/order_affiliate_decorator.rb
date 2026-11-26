# Affiliate attribution on orders: the affiliate account the order came through (set once, while
# the order is incomplete, by Affiliates::Attribution) and the commission it earned.
#
# Completion (finalize!), cancel and resume update the commission through
# Affiliates::CommissionRecorder; refunds do it from Spree::RefundAffiliateDecorator. These are
# method hooks rather than state machine callbacks, so they survive a redefined checkout flow.
# Loaded by the to_prepare decorator glob.
module Spree
  module OrderAffiliateDecorator
    def self.prepended(base)
      base.belongs_to :affiliate_account, class_name: 'AffiliateAccount', optional: true
      base.has_one :affiliate_commission, class_name: 'AffiliateCommission', foreign_key: :order_id, inverse_of: :order
    end

    # The only hook that creates a commission; the others update an existing one.
    def finalize!
      result = super
      Affiliates::CommissionRecorder.call(self, create: true)
      result
    end

    private

    def after_cancel
      result = super
      Affiliates::CommissionRecorder.call(self)
      result
    end

    def after_resume
      result = super
      Affiliates::CommissionRecorder.call(self, revive: true)
      result
    end
  end
end

Spree::Order.prepend(Spree::OrderAffiliateDecorator) unless Spree::Order.ancestors.include?(Spree::OrderAffiliateDecorator)
