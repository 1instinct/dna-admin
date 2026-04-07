class CreatePrescriptions < ActiveRecord::Migration[6.1]
  def change
    create_table :prescriptions do |t|
      t.references :patient_mapping, null: false, foreign_key: true
      t.integer :prescription_id, null: false
      t.string :drug_name, null: false
      t.string :ndc, null: false
      t.integer :written_qty
      t.integer :refills_left
      t.date :expire_date
      t.string :prescriber_name
      t.integer :status, default: 0, null: false
      t.datetime :received_at

      t.timestamps
    end

    add_index :prescriptions, :prescription_id, unique: true
    add_index :prescriptions, :ndc
    add_index :prescriptions, :status
  end
end
