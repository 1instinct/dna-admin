class CreateSpreeProductVideos < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_product_videos do |t|
      # spree_products.id is a serial (integer) column.
      t.references :product, type: :integer, null: false, index: true,
                             foreign_key: { to_table: :spree_products }
      t.integer :position
      t.string :alt

      t.timestamps
    end
  end
end
