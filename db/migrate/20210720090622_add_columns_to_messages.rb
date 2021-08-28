class AddColumnsToMessages < ActiveRecord::Migration[6.1]
  def change
    add_reference :messages, :sender, polymorphic: true, index: true
    add_reference :messages, :receiver, polymorphic: true, index: true    
  end
end
