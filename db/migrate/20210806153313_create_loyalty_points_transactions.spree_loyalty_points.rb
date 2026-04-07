# This migration comes from spree_loyalty_points (originally 20140116110437)
class CreateLoyaltyPointsTransactions < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_loyalty_points_transactions do |t|
      t.integer :loyalty_points
      t.string :transaction_type
      t.integer :user_id, null: false
      t.integer :order_id
    end
  end
end
