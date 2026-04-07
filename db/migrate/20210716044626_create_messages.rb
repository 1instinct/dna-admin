class CreateMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :messages do |t|
      t.integer :creator_id
      t.text :recipients
      t.boolean :is_received
      t.boolean :is_read
      t.integer :sentiment

      t.timestamps
    end
  end
end
