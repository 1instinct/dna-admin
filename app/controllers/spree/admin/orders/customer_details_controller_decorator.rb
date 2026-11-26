# Lets admins set an order's sales channel (Retail or Wholesale) on its Customer page; the select
# comes from app/overrides/spree/admin/orders/customer_details/_form/channel.html.erb.deface.
# Only the two known values are accepted; anything else leaves the channel unchanged.
# Loaded by the decorator glob in config/application.rb; prepending again changes nothing.
module Spree
  module Admin
    module Orders
      module CustomerDetailsControllerChannelDecorator
        private

        def order_params
          permitted = super
          channel = params.dig(:order, :channel).to_s
          permitted[:channel] = channel if Spree::OrderWholesaleChannelDecorator::CHANNELS.include?(channel)
          permitted
        end
      end
    end
  end
end

Spree::Admin::Orders::CustomerDetailsController.prepend(Spree::Admin::Orders::CustomerDetailsControllerChannelDecorator)
