# Affiliate attribution on orders, added without long locks on spree_orders: nullable columns
# (no rewrite), the index built concurrently, and the foreign keys added NOT VALID, then validated
# (which doesn't block writes).
class AddAffiliateAttributionToSpreeOrders < ActiveRecord::Migration[6.1]
  disable_ddl_transaction!

  def up
    add_column :spree_orders, :affiliate_account_id, :bigint unless column_exists?(:spree_orders, :affiliate_account_id)
    add_column :spree_orders, :affiliate_attributed_at, :datetime unless column_exists?(:spree_orders, :affiliate_attributed_at)
    unless index_exists?(:spree_orders, :affiliate_account_id)
      add_index :spree_orders, :affiliate_account_id, algorithm: :concurrently
    end

    unless foreign_key_exists?(:spree_orders, :affiliate_accounts, column: :affiliate_account_id)
      add_foreign_key :spree_orders, :affiliate_accounts, column: :affiliate_account_id, on_delete: :nullify, validate: false
    end
    validate_foreign_key :spree_orders, :affiliate_accounts, column: :affiliate_account_id

    unless foreign_key_exists?(:affiliate_commissions, :spree_orders, column: :order_id)
      add_foreign_key :affiliate_commissions, :spree_orders, column: :order_id, validate: false
    end
    validate_foreign_key :affiliate_commissions, :spree_orders, column: :order_id
  end

  def down
    remove_foreign_key :affiliate_commissions, :spree_orders, column: :order_id if foreign_key_exists?(:affiliate_commissions, :spree_orders, column: :order_id)
    remove_foreign_key :spree_orders, :affiliate_accounts, column: :affiliate_account_id if foreign_key_exists?(:spree_orders, :affiliate_accounts, column: :affiliate_account_id)
    remove_index :spree_orders, :affiliate_account_id, algorithm: :concurrently if index_exists?(:spree_orders, :affiliate_account_id)
    remove_column :spree_orders, :affiliate_attributed_at if column_exists?(:spree_orders, :affiliate_attributed_at)
    remove_column :spree_orders, :affiliate_account_id if column_exists?(:spree_orders, :affiliate_account_id)
  end
end
