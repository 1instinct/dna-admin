# This migration comes from spree_loyalty_points (originally 20140207055836)
class AddLockVersionToSpreeUser < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_users, :lock_version, :integer, default: 0, null: false unless column_exists?(:spree_users, :lock_version)
  end
end
