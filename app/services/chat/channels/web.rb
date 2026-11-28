module Chat
  module Channels
    # The storefront widget: delivering is doing nothing, since the widget polls
    # GET /api/v1/storefront/chat/messages. When the customer has left (not seen for
    # Chat.config.offline_after) and gave an email, the reply also goes out by email, so the
    # conversation can continue there.
    class Web
      def deliver(message)
        message.update_column(:delivery_status, 'sent') unless message.delivery_status
        email = Chat::Channels['email']
        email&.new&.deliver(message)
      end
    end
  end
end
