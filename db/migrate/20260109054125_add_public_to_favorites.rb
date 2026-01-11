class AddPublicToFavorites < ActiveRecord::Migration[6.1]
  def change
    add_column :favorites, :is_public, :boolean, default: false
    add_index :favorites, :is_public
  end
end
