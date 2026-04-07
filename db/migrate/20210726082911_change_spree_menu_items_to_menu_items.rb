class ChangeSpreeMenuItemsToMenuItems < ActiveRecord::Migration[6.1]
  def change
    rename_table :spree_menu_items, :menu_items
  end
end
