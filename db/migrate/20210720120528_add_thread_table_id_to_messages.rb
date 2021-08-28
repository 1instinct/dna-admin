class AddThreadTableIdToMessages < ActiveRecord::Migration[6.1]
  def change
    add_reference :messages, :thread_table, null: true, foreign_key: true
  end
end
