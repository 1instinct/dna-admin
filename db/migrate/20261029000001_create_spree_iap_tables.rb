# In-app purchases: store catalogue, verified store transactions, store
# notifications, derived entitlements and an admin audit trail. Self-contained
# (only references spree_users / spree_stores) so it ports to later Spree versions.
class CreateSpreeIapTables < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_iap_products do |t|
      t.references :store, index: true
      t.string :platform, null: false
      t.string :product_id, null: false
      t.string :kind, null: false, default: 'subscription'
      t.string :entitlement
      t.string :name
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :spree_iap_products, %i[platform product_id], unique: true, name: 'index_spree_iap_products_on_platform_product'

    create_table :spree_iap_transactions do |t|
      t.references :user, index: true
      t.references :iap_product, index: true
      t.string :platform, null: false
      t.string :product_id, null: false
      t.string :transaction_id, null: false
      t.string :original_transaction_id, null: false
      t.string :order_id
      t.string :environment, null: false, default: 'production'
      t.string :status, null: false, default: 'active'
      t.boolean :auto_renew
      t.datetime :purchased_at
      t.datetime :expires_at
      t.datetime :grace_expires_at
      t.datetime :revoked_at
      t.string :revocation_reason
      t.decimal :price, precision: 12, scale: 4
      t.string :currency
      t.text :signed_payload
      t.jsonb :payload, null: false, default: {}
      t.datetime :verified_at
      t.datetime :acknowledged_at
      t.datetime :admin_revoked_at
      t.timestamps
    end
    add_index :spree_iap_transactions, %i[platform transaction_id], unique: true, name: 'index_spree_iap_transactions_on_platform_txn'
    add_index :spree_iap_transactions, %i[platform original_transaction_id], name: 'index_spree_iap_transactions_on_platform_original'
    add_index :spree_iap_transactions, :status
    add_index :spree_iap_transactions, :created_at

    create_table :spree_iap_notifications do |t|
      t.references :iap_transaction, index: true
      t.string :platform, null: false
      t.string :notification_id, null: false
      t.string :notification_type
      t.string :subtype
      t.string :environment
      t.text :signed_payload
      t.jsonb :payload, null: false, default: {}
      t.datetime :processed_at
      t.string :error
      t.timestamps
    end
    add_index :spree_iap_notifications, %i[platform notification_id], unique: true, name: 'index_spree_iap_notifications_on_platform_notification'

    create_table :spree_entitlements do |t|
      t.references :user, null: false, index: false
      t.string :key, null: false
      t.references :iap_transaction, index: true
      t.datetime :starts_at
      t.datetime :expires_at
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_index :spree_entitlements, %i[user_id key], unique: true

    create_table :spree_iap_audit_logs do |t|
      t.references :iap_transaction, null: false, index: true
      t.references :admin_user, index: true
      t.string :action, null: false
      t.text :note
      t.timestamps
    end
  end
end
