# This migration comes from spree_loyalty_points (originally 20140131072702)
class RemoveLoyaltyPointsAwardedFromSpreeOrder < ActiveRecord::Migration[6.1]
  def change
    remove_column :spree_orders, :loyalty_points_awarded, :boolean, default: false, null: false
  end
end
