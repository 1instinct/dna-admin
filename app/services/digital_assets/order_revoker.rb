module DigitalAssets
  # Revokes ownerships an order granted. Ownership from another source (an admin grant, a free
  # claim, another order) is left alone.
  module OrderRevoker
    module_function

    # Revokes the order's ownerships, or only those of the given line items.
    def call(order, reason:, line_items: nil)
      return [] unless order&.user_id

      variant_ids = (line_items || order.line_items).map(&:variant_id)
      return [] if variant_ids.empty?

      Spree::DigitalOwnership.active
                             .where(user_id: order.user_id, variant_id: variant_ids, source: 'order',
                                    source_type: 'Spree::Order', source_id: order.id)
                             .map { |ownership| ownership.revoke!(reason) }
    end

    # Which line items a refund covers:
    # - a refund through a reimbursement: the line items of its returned units;
    # - otherwise, when the order's refunds now cover its whole total: every line item;
    # - otherwise, the first digital line item still owned whose amount (or final amount, with
    #   promotions and tax) equals the refund amount.
    # A partial refund that matches no line item revokes nothing.
    def for_refund(refund, reason: 'refunded')
      order = refund.payment&.order
      return [] unless order&.user_id

      call(order, reason: reason, line_items: refunded_line_items(order, refund))
    end

    def refunded_line_items(order, refund)
      if refund.respond_to?(:reimbursement) && refund.reimbursement
        return refund.reimbursement.return_items.map { |item| item.inventory_unit&.line_item }.compact.uniq
      end
      return order.line_items.to_a if order.refunds.sum(:amount) >= order.total

      owned = Spree::DigitalOwnership.active.where(source_type: 'Spree::Order', source_id: order.id).pluck(:variant_id)
      match = order.line_items.detect do |line_item|
        owned.include?(line_item.variant_id) &&
          [line_item.amount, line_item.final_amount].any? { |amount| amount.to_d == refund.amount.to_d }
      end
      match ? [match] : []
    end
  end
end
