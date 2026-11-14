module DigitalAssets
  # Checkout changes for digital items, made on Spree 4.2's existing order state machine.
  # Redefining checkout_flow would rebuild the machine and drop hooks other extensions added to
  # it, so this changes the machine in place:
  #
  # - Delivery skip: an order that needs no delivery (Spree::Order#delivery_required? false) goes
  #   from address straight to the step after delivery. For every transition out of delivery the
  #   same transition out of address is added to the `next` event, guarded by !delivery_required?
  #   plus the original condition, ahead of the stock branches.
  # - Account check: entering any step after address (delivery, payment, confirm, complete and any
  #   other inserted step) runs Spree::Order#ensure_digital_account first, before Spree's own
  #   callbacks (so before payments are processed). A guest order that picked up a digital item
  #   after leaving the cart stops there with "digital_requires_account".
  module CheckoutFlow
    module_function

    def install!(order_class)
      machine = order_class.state_machines[:state]
      return false unless machine
      return false if machine.instance_variable_get(:@digital_assets_installed)

      install_account_check(order_class, machine)
      install_delivery_skip(order_class, machine)
      machine.instance_variable_set(:@digital_assets_installed, true)
      true
    end

    def install_account_check(order_class, machine)
      steps = order_class.checkout_steps.keys - %i[address]
      return if steps.empty?

      machine.before_transition to: steps, do: :ensure_digital_account
      callbacks = machine.callbacks[:before]
      callbacks.unshift(callbacks.pop)
    end

    def install_delivery_skip(order_class, machine)
      event = machine.events[:next]
      return unless event && order_class.checkout_steps.key?(:address) && order_class.checkout_steps.key?(:delivery)

      branches = order_class.next_event_transitions.select { |t| t.key?(:delivery) }.map do |transition|
        condition = transition[:if]
        guard = ->(order) { !order.delivery_required? && check(order, condition) }
        event.transition(from: :address, to: transition[:delivery], if: guard)
        event.branches.pop
      end
      event.branches.unshift(*branches)
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
