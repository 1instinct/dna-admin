# Chat messages: inbound (from the customer), outbound (staff reply) or note (staff only, never
# sent). Attachments use ActiveStorage (Message has_many_attached :attachments), so no column.
class AddChatColumnsToMessages < ActiveRecord::Migration[6.1]
  def change
    add_column :messages, :direction, :string
    add_column :messages, :channel, :string
    add_column :messages, :author_id, :bigint
    add_column :messages, :external_id, :string
    add_column :messages, :read_at, :datetime
    add_column :messages, :delivery_status, :string

    add_index :messages, %i[thread_table_id id]
    add_index :messages, :author_id
    add_index :messages, :external_id
    add_foreign_key :messages, :spree_users, column: :author_id, on_delete: :nullify
  end
end
