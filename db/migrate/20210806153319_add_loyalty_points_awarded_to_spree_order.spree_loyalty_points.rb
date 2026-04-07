# This migration comes from spree_loyalty_points (originally 20140124121728)
class AddLoyaltyPointsAwardedToSpreeOrder < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_orders, :loyalty_points_awarded, :boolean, default: false, null: false
  end
end
