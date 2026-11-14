# Store credit given back through a reimbursement reduces (or voids) the order's affiliate
# commission, like a refund. Loaded by the to_prepare decorator glob.
module Spree
  module ReimbursementCreditAffiliateDecorator
    def self.prepended(base)
      base.after_create :update_affiliate_commission
    end

    private

    def update_affiliate_commission
      order_id = reimbursement&.order_id
      order = order_id && Spree::Order.find_by(id: order_id)
      Affiliates::CommissionRecorder.call(order) if order&.affiliate_account_id
    end
  end
end

unless Spree::Reimbursement::Credit.ancestors.include?(Spree::ReimbursementCreditAffiliateDecorator)
  Spree::Reimbursement::Credit.prepend(Spree::ReimbursementCreditAffiliateDecorator)
end
