# This migration comes from spree_loyalty_points (originally 20140122084005)
class AddCommentToSpreeLoyaltyPointsTransaction < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_loyalty_points_transactions, :comment, :string
  end
end
