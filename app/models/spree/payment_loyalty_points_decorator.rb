# spree_loyalty_points validates a loyalty points payment against the order user's balance. A
# retained order of a deleted account (AccountDeletion) has no user, since the user is
# soft-deleted. An existing payment was checked when it was made, so it passes instead of raising
# NoMethodError on nil whenever it is saved again (capture, void); a new one has no balance to
# redeem and is invalid.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module PaymentLoyaltyPointsDecorator
    private

    def redeemable_loyalty_points_balance?
      return persisted? if order&.user.nil?

      super
    end
  end
end

Spree::Payment.prepend(Spree::PaymentLoyaltyPointsDecorator)
