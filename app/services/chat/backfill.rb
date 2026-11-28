module Chat
  # Fills the chat columns on rows from before them (`rake chat:backfill`, once after the chat
  # migrations; safe to run again, it only fills blanks):
  #
  # 1. contacts.user_id from actor_id, where that user still exists;
  # 1. messages.direction: inbound from a contact, outbound to one (messages between two users,
  #    such as live stream chat, stay without one);
  # 1. thread_tables.contact_id: the contact in the thread's messages, which makes it a customer
  #    conversation (channel web); status closed when the thread is archived, else open;
  # 1. thread_tables.last_message_at: its newest message.
  #
  # Unread counters start at 0: older messages count as read.
  module Backfill
    module_function

    def run
      connection = ActiveRecord::Base.connection
      counts = {}
      ActiveRecord::Base.transaction do
        counts[:contacts_user] = connection.exec_update(<<~SQL)
          UPDATE contacts SET user_id = actor_id
          WHERE user_id IS NULL AND actor_id IS NOT NULL AND actor_id IN (SELECT id FROM spree_users)
        SQL
        counts[:messages_inbound] = Message.where(direction: nil, sender_type: 'Contact').update_all(direction: 'inbound')
        counts[:messages_outbound] = Message.where(direction: nil, receiver_type: 'Contact').update_all(direction: 'outbound')
        counts[:threads_contact] = connection.exec_update(<<~SQL)
          UPDATE thread_tables SET contact_id = parties.contact_id, channel = COALESCE(thread_tables.channel, 'web'),
                                   status = CASE WHEN thread_tables.archived THEN 'closed' ELSE 'open' END
          FROM (
            SELECT thread_table_id,
                   MIN(CASE WHEN sender_type = 'Contact' THEN sender_id ELSE receiver_id END) AS contact_id
            FROM messages
            WHERE thread_table_id IS NOT NULL AND (sender_type = 'Contact' OR receiver_type = 'Contact')
            GROUP BY thread_table_id
          ) parties
          WHERE thread_tables.id = parties.thread_table_id AND thread_tables.contact_id IS NULL
            AND parties.contact_id IN (SELECT id FROM contacts)
        SQL
        counts[:threads_last_message_at] = connection.exec_update(<<~SQL)
          UPDATE thread_tables SET last_message_at = latest.created_at
          FROM (SELECT thread_table_id, MAX(created_at) AS created_at FROM messages WHERE thread_table_id IS NOT NULL GROUP BY thread_table_id) latest
          WHERE thread_tables.id = latest.thread_table_id AND thread_tables.last_message_at IS NULL
        SQL
      end
      counts
    end
  end
end
