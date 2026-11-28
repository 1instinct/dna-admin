# A contact is a person on the storefront: a visitor (by the widget's visitor_token), a customer
# who wrote in, or both. user_id links the signed-in account; actor_id stays for older code and is
# kept in step with it by Contact.
class AddChatColumnsToContacts < ActiveRecord::Migration[6.1]
  def change
    add_column :contacts, :visitor_token, :string
    add_column :contacts, :name, :string
    add_column :contacts, :user_id, :bigint
    add_column :contacts, :last_seen_at, :datetime
    add_column :contacts, :email_opt_in, :boolean, null: false, default: false

    add_index :contacts, :visitor_token, unique: true
    add_index :contacts, :user_id
    add_index :contacts, :last_seen_at
    add_foreign_key :contacts, :spree_users, column: :user_id, on_delete: :nullify
  end
end
