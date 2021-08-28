# This migration comes from spree_loyalty_points (originally 20140123120355)
class AddLoyaltyPointsToSpreeReturnAuthorization < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_return_authorizations, :loyalty_points, :integer, default: 0, null: false
    add_column :spree_return_authorizations, :loyalty_points_transaction_type, :string
  end
end
