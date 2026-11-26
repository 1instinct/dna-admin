module DigitalAssets
  # Gives the order's user one ownership per line item whose variant has a published asset.
  # Safe to run any number of times (DigitalOwnership.grant! returns the active row).
  #
  # An item whose ownership from this order was revoked for any reason other than the order's
  # cancel (a refund, an admin) is not granted again, so resuming a canceled order restores only
  # what the cancel took away.
  module OrderGranter
    module_function

    REGRANTABLE_REASONS = ['order_canceled'].freeze

    def call(order)
      return [] unless order&.completed? && !order.canceled? && order.user_id

      withheld = withheld_variant_ids(order)
      order.line_items.includes(:variant).filter_map do |line_item|
        next unless line_item.variant&.digital?
        next if withheld.include?(line_item.variant_id)

        Spree::DigitalOwnership.grant!(user: order.user, variant: line_item.variant, source: 'order',
                                       source_record: order)
      end
    end

    def withheld_variant_ids(order)
      Spree::DigitalOwnership.revoked
                             .where(user_id: order.user_id, source_type: 'Spree::Order', source_id: order.id)
                             .where('revoke_reason IS NULL OR revoke_reason NOT IN (?)', REGRANTABLE_REASONS)
                             .distinct.pluck(:variant_id)
    end
  end
end
