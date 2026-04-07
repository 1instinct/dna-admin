class AddMessageToMessages < ActiveRecord::Migration[6.1]
  def change
    add_column :messages, :message, :text
  end
end
