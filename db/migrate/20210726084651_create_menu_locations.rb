class CreateMenuLocations < ActiveRecord::Migration[6.1]
  def change
    create_table :menu_locations do |t|
      t.string :title
      t.string :location
      t.boolean :is_visible

      t.timestamps
    end
  end
end
