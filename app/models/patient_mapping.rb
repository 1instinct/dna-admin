class PatientMapping < ApplicationRecord
  belongs_to :spree_user, class_name: "Spree::User", optional: true

  has_many :prescriptions, dependent: :destroy
  has_many :pharmacy_orders, dependent: :destroy

  enum source: {
    rx_received: 0,
    mdi_webhook: 1,
    manual: 2
  }

  validates :honeybee_patient_id, presence: true, uniqueness: true
  validates :source, presence: true
end
