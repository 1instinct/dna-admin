class AddConsultationFieldsToSpreeUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_users, :consultation_status, :integer, default: 0, null: false
    add_column :spree_users, :mdi_encounter_id, :string
    add_column :spree_users, :consultation_completed_at, :datetime
    add_column :spree_users, :honeybee_patient_id, :string

    add_index :spree_users, :consultation_status
    add_index :spree_users, :mdi_encounter_id, unique: true, where: "mdi_encounter_id IS NOT NULL"
    add_index :spree_users, :honeybee_patient_id, unique: true, where: "honeybee_patient_id IS NOT NULL"
  end
end
