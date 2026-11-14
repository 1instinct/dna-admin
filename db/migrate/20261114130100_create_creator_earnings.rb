# The creator earnings ledger (one row per sold line item of a creator product) and the payouts
# that settle it. Payouts are recorded by an admin after paying outside the app.
class CreateCreatorEarnings < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_creator_payouts do |t|
      t.references :creator_account, null: false, index: true, foreign_key: { to_table: :spree_creator_accounts }
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.string :reference, null: false
      t.datetime :paid_at, null: false
      t.text :note

      t.timestamps
    end

    create_table :spree_creator_earnings do |t|
      t.references :creator_account, null: false, index: true, foreign_key: { to_table: :spree_creator_accounts }
      # No foreign keys to Spree orders and line items: an admin editing a completed order must not
      # be blocked by the ledger.
      t.references :order, type: :integer, null: false, index: true
      t.references :line_item, type: :integer, null: false, index: { unique: true }
      t.decimal :gross, precision: 10, scale: 2, null: false
      t.integer :share_bps, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.string :state, null: false, default: 'pending'
      t.datetime :payable_at, null: false
      t.references :creator_payout, index: true, foreign_key: { to_table: :spree_creator_payouts }

      t.timestamps
    end
    add_index :spree_creator_earnings, %i[state payable_at]
    add_index :spree_creator_earnings, %i[creator_account_id created_at], name: 'index_spree_creator_earnings_on_account_and_created_at'
  end
end
