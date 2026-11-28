module Spree
  module Admin
    # The sidebar's Inbox entry and its unread count.
    module InboxHelper
      # Conversations (not closed) with customer messages staff haven't read; 0 when the chat
      # tables aren't there.
      def admin_inbox_unread_count
        ThreadTable.conversations.not_closed.where('staff_unread_count > 0').count
      rescue ActiveRecord::ActiveRecordError
        0
      end
    end
  end
end
