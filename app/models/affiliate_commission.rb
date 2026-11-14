# What an affiliate earns on one attributed order.
#
# base_amount: the item total after promotions, without shipping or tax, less refunds.
# amount: base_amount * commission_bps / 10000, rounded to cents.
# state: pending -> approved (after approvable_at, see .sweep!) -> paid (in a payout); void when the
#        order is canceled or fully refunded, or by an admin.
class AffiliateCommission < ApplicationRecord
  STATES = %w[pending approved paid void].freeze

  belongs_to :affiliate_account
  belongs_to :order, class_name: 'Spree::Order'
  belongs_to :payout, class_name: 'AffiliatePayout', foreign_key: :affiliate_payout_id, optional: true,
                      inverse_of: :commissions

  validates :state, inclusion: { in: STATES }
  validates :order_id, uniqueness: true
  validates :commission_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true

  STATES.each do |name|
    scope name, -> { where(state: name) }
    define_method("#{name}?") { state == name }
  end

  # Approves pending commissions whose hold has passed. Returns how many changed.
  def self.sweep!(now: Time.current)
    pending.where('approvable_at <= ?', now).update_all(state: 'approved', updated_at: now)
  end

  def self.amount_for(base_amount, bps)
    (base_amount.to_d * bps.to_i / 10_000).round(2)
  end

  # The order number reduced to its last four characters; affiliates never see who bought.
  def order_masked
    number = order&.number.to_s
    "****#{number[-4..] || number}"
  end
end
