# A payment made to a creator outside the app, recorded with its reference. The earnings it
# settled point at it (creator_payout_id) and are paid. See Creators::Payouts.
module Spree
  class CreatorPayout < Spree::Base
    self.table_name = 'spree_creator_payouts'

    belongs_to :creator_account, class_name: 'Spree::CreatorAccount'
    has_many :earnings, class_name: 'Spree::CreatorEarning', foreign_key: :creator_payout_id, inverse_of: :payout,
                        dependent: :restrict_with_error

    validates :amount, numericality: { greater_than: 0 }
    validates :currency, :paid_at, presence: true
    validates :reference, presence: true, length: { maximum: 255 }
    validates :note, length: { maximum: 2000 }
  end
end
