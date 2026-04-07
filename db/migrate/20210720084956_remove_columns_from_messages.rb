class RemoveColumnsFromMessages < ActiveRecord::Migration[6.1]
  def change
    remove_column :messages, :creator_id, :integer
    remove_column :messages, :recipients, :text
  end
end
