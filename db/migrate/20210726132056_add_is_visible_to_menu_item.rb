class AddIsVisibleToMenuItem < ActiveRecord::Migration[6.1]
  def change
    add_column :menu_items, :is_visible, :boolean
  end
end
