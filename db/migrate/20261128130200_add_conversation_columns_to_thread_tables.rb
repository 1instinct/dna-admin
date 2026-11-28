# A thread with a contact is a customer conversation (Chat::Conversations). Threads without one
# (live stream chats, older two-party threads) are left as they were.
class AddConversationColumnsToThreadTables < ActiveRecord::Migration[6.1]
  def change
    add_column :thread_tables, :contact_id, :bigint
    add_column :thread_tables, :status, :string, null: false, default: 'open'
    add_column :thread_tables, :channel, :string
    add_column :thread_tables, :subject, :string
    add_column :thread_tables, :assignee_id, :bigint
    add_column :thread_tables, :snoozed_until, :datetime
    add_column :thread_tables, :last_message_at, :datetime
    add_column :thread_tables, :staff_unread_count, :integer, null: false, default: 0
    add_column :thread_tables, :customer_unread_count, :integer, null: false, default: 0
    add_column :thread_tables, :visitor_session_id, :bigint

    add_index :thread_tables, :contact_id
    add_index :thread_tables, :assignee_id
    add_index :thread_tables, :visitor_session_id
    add_index :thread_tables, %i[status last_message_at]
    add_index :thread_tables, :updated_at
    add_foreign_key :thread_tables, :contacts, on_delete: :nullify
    add_foreign_key :thread_tables, :spree_users, column: :assignee_id, on_delete: :nullify
    add_foreign_key :thread_tables, :visitor_sessions, on_delete: :nullify
  end
end
