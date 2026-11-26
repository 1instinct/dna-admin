module Reviews
  # What a customer may review: products from line items that have shipped, on completed orders
  # that weren't canceled. One entry per product (a product bought twice, or in two variants, is
  # reviewed once, against its most recent purchase). Admin accounts may not review products.
  #
  #   Reviews::Eligibility.for_user(user)    # signed in: across all their orders
  #   Reviews::Eligibility.for_order(order)  # the email link: that order only
  #   Reviews::Eligibility.item(user: u, order: o, product: p, line_item_id: id) # one, or nil
  module Eligibility
    Item = Struct.new(:line_item, :order, :product, :variant, :existing_review, keyword_init: true)

    module_function

    def for_user(user)
      return [] if user.nil? || user.admin?

      items(shipped_line_items.where(spree_orders: { user_id: user.id }), user: user)
    end

    def for_order(order)
      return [] if order.nil? || order.user&.admin?

      items(shipped_line_items.where(spree_orders: { id: order.id }), user: order.user, order: order)
    end

    # The eligible purchase of `product`, from `order` when given (the email link), else from any
    # of the user's orders. With line_item_id, that line item must be the one.
    def item(product:, user: nil, order: nil, line_item_id: nil)
      list = order ? for_order(order) : for_user(user)
      list.find do |entry|
        entry.product.id == product.id && (line_item_id.blank? || entry.line_item.id == line_item_id.to_i)
      end
    end

    # The most recent completed order with something shipped, for store reviews.
    def latest_shipped_order(user)
      return if user.nil? || user.admin?

      shipped_line_items.where(spree_orders: { user_id: user.id }).order('spree_orders.completed_at DESC').first&.order
    end

    def shipped_line_items
      Spree::LineItem.joins(:order, inventory_units: :shipment).
        where(spree_orders: { state: 'complete' }).
        where.not(spree_orders: { completed_at: nil }).
        where(spree_shipments: { state: 'shipped' }).
        includes(:order, variant: :product).
        distinct
    end

    def items(line_items, user:, order: nil)
      latest = line_items.to_a.
               reject { |li| li.variant&.product.nil? }.
               sort_by { |li| [li.order.completed_at, li.id] }.
               reverse.
               uniq { |li| li.variant.product_id }
      return [] if latest.empty?

      reviews = existing_reviews(latest.map { |li| li.variant.product_id }, user: user, order: order)
      latest.map do |li|
        product = li.variant.product
        Item.new(line_item: li, order: li.order, product: product, variant: li.variant,
                 existing_review: reviews[product.id])
      end
    end

    # The customer's own reviews of these products: by user when signed in, else by order.
    def existing_reviews(product_ids, user:, order:)
      scope = Spree::Review.for_products.where(reviewable_id: product_ids)
      scope = if user
                scope.where(user_id: user.id)
              else
                scope.where(order_id: order.id)
              end
      scope.index_by(&:reviewable_id)
    end
  end
end
