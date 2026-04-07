class CreatePharmacyOrders < ActiveRecord::Migration[6.1]
  def change
    create_table :pharmacy_orders do |t|
      t.references :spree_user, foreign_key: { to_table: :spree_users }
      t.references :spree_order, foreign_key: { to_table: :spree_orders }
      t.references :patient_mapping, null: false, foreign_key: true
      t.string :honeybee_order_number, null: false
      t.integer :prescription_ids, array: true, default: []
      t.string :status
      t.jsonb :shipment_data, default: {}
      t.jsonb :exception_data, default: {}

      t.timestamps
    end

    add_index :pharmacy_orders, :honeybee_order_number, unique: true
    add_index :pharmacy_orders, [:patient_mapping_id, :created_at],
              name: "index_pharmacy_orders_on_patient_mapping_and_created_at"
  end
end
