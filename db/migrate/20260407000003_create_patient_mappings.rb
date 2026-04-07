class CreatePatientMappings < ActiveRecord::Migration[6.1]
  def change
    create_table :patient_mappings do |t|
      t.string :honeybee_patient_id, null: false
      t.references :spree_user, foreign_key: { to_table: :spree_users }
      t.string :email
      t.string :mdi_encounter_id
      t.integer :source, null: false
      t.jsonb :history, default: []

      t.timestamps
    end

    add_index :patient_mappings, :honeybee_patient_id, unique: true
    add_index :patient_mappings, :email
    add_index :patient_mappings, :mdi_encounter_id
  end
end
