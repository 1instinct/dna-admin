class PendingCustomer < ApplicationRecord
  belongs_to :spree_user, class_name: "Spree::User", optional: true
  belongs_to :spree_order, class_name: "Spree::Order", optional: true

  validates :email, presence: true, uniqueness: true
  validates :mdi_encounter_id, presence: true
end
