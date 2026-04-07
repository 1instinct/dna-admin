class PharmacyOrder < ApplicationRecord
  belongs_to :spree_user, class_name: "Spree::User", optional: true
  belongs_to :spree_order, class_name: "Spree::Order", optional: true
  belongs_to :patient_mapping

  validates :honeybee_order_number, presence: true, uniqueness: true
end
