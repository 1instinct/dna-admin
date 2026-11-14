module DigitalAssets
  # Lets an order that needs no delivery (Spree::Order#delivery_required? false) go from address
  # straight to the step after delivery. Spree 4.2's flow has an unconditional address -> delivery
  # transition, and redefining checkout_flow would rebuild the state machine and drop hooks other
  # extensions added to it, so this adds branches to the existing `next` event instead: for every
  # transition out of delivery, the same transition out of address, guarded by
  # !delivery_required? plus the original condition, placed before the stock branches.
  module CheckoutFlow
    module_function

    def install!(order_class)
      machine = order_class.state_machines[:state]
      event = machine&.events&.[](:next)
      return false unless event && order_class.checkout_steps.key?(:address) && order_class.checkout_steps.key?(:delivery)
      return false if event.instance_variable_get(:@digital_assets_skip_delivery)

      branches = order_class.next_event_transitions.select { |t| t.key?(:delivery) }.map do |transition|
        condition = transition[:if]
        guard = ->(order) { !order.delivery_required? && check(order, condition) }
        event.transition(from: :address, to: transition[:delivery], if: guard)
        event.branches.pop
      end
      event.branches.unshift(*branches)
      event.instance_variable_set(:@digital_assets_skip_delivery, true)
      true
    end

    def check(order, condition)
      case condition
      when nil then true
      when Symbol, String then order.send(condition)
      else condition.call(order)
      end
    end
  end
end
