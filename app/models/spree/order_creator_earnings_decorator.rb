# Creator earnings on orders: completion (finalize!) records them, cancel voids them and resume
# brings them back, through Creators::EarningsRecorder, which logs and swallows its own errors so
# checkout never fails on them. Refunds are handled in Spree::RefundCreatorEarningsDecorator.
# Method hooks rather than state machine callbacks, so a redefined checkout flow keeps them.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module OrderCreatorEarningsDecorator
    def finalize!
      result = super
      Creators::EarningsRecorder.call(self)
      result
    end

    def after_cancel
      result = super
      Creators::EarningsRecorder.call(self)
      result
    end

    def after_resume
      result = super
      Creators::EarningsRecorder.call(self, revive: true)
      result
    end
  end
end

Spree::Order.prepend(Spree::OrderCreatorEarningsDecorator) unless Spree::Order.include?(Spree::OrderCreatorEarningsDecorator)
