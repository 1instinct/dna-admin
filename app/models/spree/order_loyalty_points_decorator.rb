# spree_loyalty_points records a loyalty transaction on the order's user. A retained order of a
# deleted account (AccountDeletion) has no user, since the user is soft-deleted, so there is no
# balance to credit or debit: skip it instead of raising NoMethodError on nil. Covers the
# payment state transitions, loyalty refunds and the points award job.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module OrderLoyaltyPointsDecorator
    def create_credit_transaction(points)
      return if user.nil?

      super
    end

    def create_debit_transaction(points)
      return if user.nil?

      super
    end
  end
end

Spree::Order.prepend(Spree::OrderLoyaltyPointsDecorator)
