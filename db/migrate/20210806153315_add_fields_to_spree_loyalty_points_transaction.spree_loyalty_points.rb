# This migration comes from spree_loyalty_points (originally 20140117065314)
class AddFieldsToSpreeLoyaltyPointsTransaction < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_loyalty_points_transactions, :source_type, :string
    rename_column :spree_loyalty_points_transactions, :order_id, :source_id
    add_column :spree_loyalty_points_transactions, :updated_balance, :integer, default: 0, null: false
  end
end
