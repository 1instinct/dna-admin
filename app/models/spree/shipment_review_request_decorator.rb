# When a shipment ships, schedule the order's review request email (ReviewRequests::Schedule).
# Spree 4.2 has no delivered state, so the email is timed from shipped_at. `after_ship` runs both
# from the `ship` state transition and from Shipment#update! (OrderUpdater), after the shipped
# state is saved, which Reviews::Eligibility needs.
#
# Never breaks shipping: scheduling runs in a savepoint, and any error is logged and swallowed.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module ShipmentReviewRequestDecorator
    private

    def after_ship
      super
      schedule_review_request
    end

    def schedule_review_request
      Spree::ReviewRequest.transaction(requires_new: true) { ReviewRequests::Schedule.call(order) }
    rescue StandardError => e
      Rails.logger.error("[reviews] review request scheduling failed order_id=#{order_id}: #{e.class}: #{e.message}")
      nil
    end
  end
end

Spree::Shipment.prepend(Spree::ShipmentReviewRequestDecorator)
