# Marks a wholesale account's orders as channel "wholesale" when they complete, so the order
# itself records how it was sold (reporting, review channel) even if the role is later removed.
# Admins can also set the channel by hand on the order's Customer page, for phone, email or
# invoice orders. A channel that is already something other than Spree's default "spree" is
# kept: completion never overwrites an admin's choice.
#
# The storefront can't set channel: it isn't in Spree's permitted checkout attributes, and the v2
# cart and checkout endpoints only accept those.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module OrderWholesaleChannelDecorator
    CHANNELS = %w[spree wholesale].freeze
    DEFAULT_CHANNEL = 'spree'.freeze

    def finalize!
      assign_wholesale_channel
      super
    end

    def wholesale_channel?
      channel.to_s == 'wholesale'
    end

    private

    def assign_wholesale_channel
      return unless channel.blank? || channel == DEFAULT_CHANNEL
      return unless Reviews::Channel.wholesale_user?(user)

      update_column(:channel, 'wholesale')
    end
  end
end

Spree::Order.prepend(Spree::OrderWholesaleChannelDecorator)
