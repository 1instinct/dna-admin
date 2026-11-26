# Affiliate attribution on orders, added without long locks on spree_orders: nullable columns
# (no rewrite), the index built concurrently, and the foreign keys added NOT VALID, then validated
# (which doesn't block writes).
class AddAffiliateAttributionToSpreeOrders < ActiveRecord::Migration[6.1]
  disable_ddl_transaction!

  # Lock waits give up after 5 s (the release phase fails and can be retried) instead of queueing
  # every request on spree_orders behind a migration stuck on a long transaction. The concurrent
  # index build runs without the timeout: one that timed out would leave an invalid index, which
  # index_exists? would then skip on the retry.
  def up
    execute "SET lock_timeout = '5s'"
    add_column :spree_orders, :affiliate_account_id, :bigint unless column_exists?(:spree_orders, :affiliate_account_id)
    add_column :spree_orders, :affiliate_attributed_at, :datetime unless column_exists?(:spree_orders, :affiliate_attributed_at)
    unless index_exists?(:spree_orders, :affiliate_account_id)
      without_lock_timeout { add_index :spree_orders, :affiliate_account_id, algorithm: :concurrently }
    end

    unless foreign_key_exists?(:spree_orders, :affiliate_accounts, column: :affiliate_account_id)
      add_foreign_key :spree_orders, :affiliate_accounts, column: :affiliate_account_id, on_delete: :nullify, validate: false
    end
    validate_foreign_key :spree_orders, :affiliate_accounts, column: :affiliate_account_id

    unless foreign_key_exists?(:affiliate_commissions, :spree_orders, column: :order_id)
      add_foreign_key :affiliate_commissions, :spree_orders, column: :order_id, validate: false
    end
    validate_foreign_key :affiliate_commissions, :spree_orders, column: :order_id
  ensure
    execute 'RESET lock_timeout'
  end

  def without_lock_timeout
    execute 'SET lock_timeout = 0'
    yield
  ensure
    execute "SET lock_timeout = '5s'"
  end

  def down
    remove_foreign_key :affiliate_commissions, :spree_orders, column: :order_id if foreign_key_exists?(:affiliate_commissions, :spree_orders, column: :order_id)
    remove_foreign_key :spree_orders, :affiliate_accounts, column: :affiliate_account_id if foreign_key_exists?(:spree_orders, :affiliate_accounts, column: :affiliate_account_id)
    remove_index :spree_orders, :affiliate_account_id, algorithm: :concurrently if index_exists?(:spree_orders, :affiliate_account_id)
    remove_column :spree_orders, :affiliate_attributed_at if column_exists?(:spree_orders, :affiliate_attributed_at)
    remove_column :spree_orders, :affiliate_account_id if column_exists?(:spree_orders, :affiliate_account_id)
  end
end
