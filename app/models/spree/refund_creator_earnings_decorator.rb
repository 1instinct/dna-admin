# A refund voids the creator earnings of the line items it covers (Creators::EarningsRecorder
# .for_refund, which logs and swallows its errors: the money has already moved).
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module RefundCreatorEarningsDecorator
    def self.prepended(base)
      base.after_create :void_creator_earnings
    end

    private

    def void_creator_earnings
      Creators::EarningsRecorder.for_refund(self)
      nil
    end
  end
end

Spree::Refund.prepend(Spree::RefundCreatorEarningsDecorator) unless Spree::Refund.include?(Spree::RefundCreatorEarningsDecorator)
