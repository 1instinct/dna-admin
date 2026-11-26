# A manual payment to an affiliate (made outside the app), covering approved commissions.
class AffiliatePayout < ApplicationRecord
  belongs_to :affiliate_account
  has_many :commissions, class_name: 'AffiliateCommission', foreign_key: :affiliate_payout_id, inverse_of: :payout,
                         dependent: :nullify

  validates :amount, numericality: { greater_than: 0 }
  validates :currency, presence: true
end
