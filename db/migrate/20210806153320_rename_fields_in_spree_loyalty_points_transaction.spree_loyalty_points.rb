# This migration comes from spree_loyalty_points (originally 20140130131957)
class RenameFieldsInSpreeLoyaltyPointsTransaction < ActiveRecord::Migration[6.1]
  def change
    rename_column :spree_loyalty_points_transactions, :updated_balance, :balance
    rename_column :spree_loyalty_points_transactions, :transaction_type, :type
  end
end
