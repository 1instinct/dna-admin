# This migration comes from spree (originally 20210622190009)
class AddWholesalePrice < ActiveRecord::Migration[6.1]
  def change
    unless column_exists?(:spree_prices, :wholesale_price)
      add_column :spree_prices, :wholesale_price, :decimal, precision: 10, scale: 2
    end
  end
end
