class CreateContacts < ActiveRecord::Migration[6.1]
  def change
    create_table :contacts do |t|
      t.integer :actor_id
      t.string :full_name
      t.text :email
      t.text :phone
      t.text :ip

      t.timestamps
    end
  end
end
