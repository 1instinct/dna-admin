module DigitalAssets
  # Gives the order's user one ownership per line item whose variant has a published asset.
  # Safe to run any number of times (DigitalOwnership.grant! returns the active row).
  module OrderGranter
    module_function

    def call(order)
      return [] unless order&.completed? && !order.canceled? && order.user_id

      order.line_items.includes(:variant).filter_map do |line_item|
        next unless line_item.variant&.digital?

        Spree::DigitalOwnership.grant!(user: order.user, variant: line_item.variant, source: 'order',
                                       source_record: order)
      end
    end
  end
end
