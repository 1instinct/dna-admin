# Affiliate program on its own tables (Affiliates module). The older spree_affiliates,
# spree_commissions, spree_commission_rules, spree_affiliate_commission_rules,
# spree_commission_transactions, spree_referrals, spree_referred_records and
# spree_affiliates_promotion_rules tables (spree_reffiliate) are left as they are.
class CreateAffiliateTables < ActiveRecord::Migration[6.1]
  def change
    create_table :affiliate_accounts do |t|
      t.integer :user_id, null: false
      t.string :code, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :commission_bps
      t.integer :cookie_days, null: false, default: 30
      t.jsonb :application, null: false, default: {}
      t.string :payout_email
      t.datetime :approved_at
      t.integer :reviewed_by_id
      t.text :review_note
      t.timestamps
    end

    add_index :affiliate_accounts, :user_id, unique: true
    add_index :affiliate_accounts, :code, unique: true
    add_index :affiliate_accounts, :status

    # visitor_hash is a salted SHA-256 of IP and user agent that changes daily; raw IPs are never stored.
    create_table :affiliate_clicks do |t|
      t.references :affiliate_account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :landing_path
      t.string :referrer_host
      t.string :visitor_hash
      t.datetime :created_at, null: false
    end

    add_index :affiliate_clicks, %i[affiliate_account_id created_at], name: 'index_affiliate_clicks_on_account_and_created_at'

    create_table :affiliate_payouts do |t|
      t.references :affiliate_account, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.string :reference
      t.datetime :paid_at
      t.text :note
      t.timestamps
    end

    create_table :affiliate_commissions do |t|
      t.references :affiliate_account, null: false, foreign_key: true, index: false
      t.integer :order_id, null: false
      t.decimal :base_amount, precision: 10, scale: 2, null: false, default: 0
      t.integer :commission_bps, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false, default: 0
      t.string :currency, null: false
      t.string :state, null: false, default: 'pending'
      # Why a void commission is void: order_canceled | refunded | admin. Only order_canceled
      # comes back on a resume.
      t.string :void_reason
      t.datetime :approvable_at
      t.references :affiliate_payout, foreign_key: true
      t.timestamps
    end

    add_index :affiliate_commissions, :order_id, unique: true
    add_index :affiliate_commissions, %i[affiliate_account_id created_at], name: 'index_affiliate_commissions_on_account_and_created_at'
    add_index :affiliate_commissions, %i[state approvable_at]

    # Fixed-window counters for Affiliates::RateLimit, one row per key ("click:<visitor hash>").
    create_table :affiliate_rate_counters do |t|
      t.string :key, null: false
      t.datetime :window_started_at, null: false
      t.integer :hits, null: false, default: 0
    end

    add_index :affiliate_rate_counters, :key, unique: true
    add_index :affiliate_rate_counters, :window_started_at

    # The spree_orders columns and the foreign keys to spree_orders are in
    # AddAffiliateAttributionToSpreeOrders, which avoids long locks on spree_orders.
  end
end
