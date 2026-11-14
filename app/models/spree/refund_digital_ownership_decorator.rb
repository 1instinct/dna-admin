# A refund that covers a digital line item revokes its ownership (reason "refunded"); see
# DigitalAssets::OrderRevoker.for_refund for what "covers" means. A failure is logged, never
# raised: the money has already moved.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module RefundDigitalOwnershipDecorator
    def self.prepended(base)
      base.after_create :revoke_digital_ownerships
    end

    private

    def revoke_digital_ownerships
      DigitalAssets::OrderRevoker.for_refund(self)
    rescue StandardError => e
      Rails.logger.error("[digital_assets] refund revoke failed for refund #{id}: #{e.class}")
      nil
    end
  end
end

Spree::Refund.prepend(Spree::RefundDigitalOwnershipDecorator) unless Spree::Refund.include?(Spree::RefundDigitalOwnershipDecorator)
