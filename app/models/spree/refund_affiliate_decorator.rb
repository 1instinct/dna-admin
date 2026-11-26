# A refund on an attributed order reduces (or voids) its affiliate commission.
# Runs after Spree's own after_create :perform!. Loaded by the to_prepare decorator glob.
module Spree
  module RefundAffiliateDecorator
    def self.prepended(base)
      base.after_create :update_affiliate_commission
    end

    private

    def update_affiliate_commission
      order = payment && Spree::Order.find_by(id: payment.order_id)
      Affiliates::CommissionRecorder.call(order) if order&.affiliate_account_id
    end
  end
end

Spree::Refund.prepend(Spree::RefundAffiliateDecorator) unless Spree::Refund.ancestors.include?(Spree::RefundAffiliateDecorator)
