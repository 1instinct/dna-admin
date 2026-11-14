# Digital line items on orders:
# - completing an order (finalize!) or resuming a canceled one grants ownership of each digital
#   line item; canceling revokes it (reason "order_canceled");
# - an order needs no delivery when every line item is digital: delivery_required? is false, the
#   delivery step is skipped (DigitalAssets::CheckoutFlow) and left out of checkout_steps;
# - a guest order holding a digital item cannot leave the cart, nor enter any later step if the
#   item was added after it left the cart: errors[:base] gets "digital_requires_account" (a 422
#   from the storefront API). When adding an item sends such an order back to the cart
#   (restart_checkout_flow), it stays in the cart instead of raising on the refused transition.
# Grant and revoke failures are logged, never raised, and run in a savepoint so a database error
# cannot abort the transaction the order's own transition is in.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module OrderDigitalOwnershipDecorator
    DIGITAL_REQUIRES_ACCOUNT = 'digital_requires_account'.freeze

    def self.prepended(base)
      DigitalAssets::CheckoutFlow.install!(base)
    end

    def digital_line_items
      line_items.includes(variant: :digital_assets).select { |line_item| line_item.variant&.digital? }
    end

    def delivery_required?
      items = line_items.includes(variant: :digital_assets).to_a
      items.empty? || !items.all? { |line_item| line_item.variant&.digital? }
    end

    def checkout_steps
      steps = super
      delivery_required? ? steps : steps - ['delivery']
    end

    def finalize!
      super
      digital_ownership_hook('grant') { DigitalAssets::OrderGranter.call(self) }
    end

    def ensure_line_items_present
      result = super
      return result if result == false

      ensure_digital_account
    end

    # false (with errors[:base] "digital_requires_account") for a guest order holding a digital item.
    def ensure_digital_account
      return true unless guest_with_digital_items?

      errors.add(:base, DIGITAL_REQUIRES_ACCOUNT) unless errors.added?(:base, DIGITAL_REQUIRES_ACCOUNT)
      false
    end

    def restart_checkout_flow
      return super unless guest_with_digital_items?

      update_columns(state: 'cart', updated_at: Time.current)
    end

    def after_cancel
      super
      digital_ownership_hook('revoke') { DigitalAssets::OrderRevoker.call(self, reason: 'order_canceled') }
    end

    def after_resume
      super
      digital_ownership_hook('grant') { DigitalAssets::OrderGranter.call(self) }
    end

    private

    def guest_with_digital_items?
      user_id.nil? && digital_line_items.any?
    end

    def digital_ownership_hook(action)
      ActiveRecord::Base.transaction(requires_new: true) { yield }
    rescue StandardError => e
      Rails.logger.error("[digital_assets] #{action} failed for order #{id}: #{e.class}")
      nil
    end
  end
end

Spree::Order.prepend(Spree::OrderDigitalOwnershipDecorator) unless Spree::Order.include?(Spree::OrderDigitalOwnershipDecorator)
