# This migration comes from spree_loyalty_points (originally 20140116090042)
class AddLoyaltyPointsBalanceToSpreeUser < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_users, :loyalty_points_balance, :integer, default: 0, null: false
  end
end
