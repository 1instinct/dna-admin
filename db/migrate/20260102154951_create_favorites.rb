class CreateFavorites < ActiveRecord::Migration[6.1]
  def change
    create_table :favorites do |t|
      t.references :user, null: false, foreign_key: { to_table: :spree_users }
      t.references :variant, null: false, foreign_key: { to_table: :spree_variants }
      t.timestamps
    end

    add_index :favorites, [:user_id, :variant_id], unique: true, name: 'index_favorites_on_user_and_variant'
  end
end
