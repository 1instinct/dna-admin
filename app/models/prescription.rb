class Prescription < ApplicationRecord
  belongs_to :patient_mapping

  has_one :spree_user, through: :patient_mapping, source: :spree_user

  enum status: {
    pending: 0,
    ordered: 1,
    filling: 2,
    ready: 3,
    shipped: 4,
    delivered: 5,
    cancelled: 6
  }

  validates :prescription_id, presence: true, uniqueness: true
  validates :drug_name, presence: true
  validates :ndc, presence: true
end
