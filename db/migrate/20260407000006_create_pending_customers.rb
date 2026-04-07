class CreatePendingCustomers < ActiveRecord::Migration[6.1]
  def change
    create_table :pending_customers do |t|
      t.string :email, null: false
      t.references :spree_user, foreign_key: { to_table: :spree_users }
      t.references :spree_order, foreign_key: { to_table: :spree_orders }
      t.string :mdi_encounter_id, null: false
      t.jsonb :patient_info, default: {}

      t.timestamps
    end

    add_index :pending_customers, :email, unique: true
    add_index :pending_customers, :mdi_encounter_id
  end
end
