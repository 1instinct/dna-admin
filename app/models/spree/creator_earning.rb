# What a creator earns on one sold line item of their product.
#
# gross:  the line item's amount after its own and its share of the order's promotions;
#         refunded_gross is the part of it refunded since (partial refunds and returns).
# amount: (gross - refunded_gross) * share_bps / 10000, rounded to cents (share_bps is the account's share at the sale).
# state:  pending -> payable (after payable_at = completion + Creators.config.hold_days, see .sweep!)
#         -> paid (in a payout); void when the order is canceled, the line item refunded or an
#         admin voids it (void_reason cancel | refund | admin; a resume revives only cancel).
# One row per line item (unique index); Creators::EarningsRecorder keeps it in step with the order.
module Spree
  class CreatorEarning < Spree::Base
    STATES = %w[pending payable paid void].freeze
    VOID_REASONS = %w[cancel refund admin].freeze

    self.table_name = 'spree_creator_earnings'

    belongs_to :creator_account, class_name: 'Spree::CreatorAccount'
    belongs_to :order, class_name: 'Spree::Order', optional: true
    belongs_to :line_item, class_name: 'Spree::LineItem', optional: true
    belongs_to :payout, class_name: 'Spree::CreatorPayout', foreign_key: :creator_payout_id, optional: true,
                        inverse_of: :earnings

    validates :state, inclusion: { in: STATES }
    validates :line_item_id, uniqueness: true
    validates :share_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000 }
    validates :gross, :amount, :currency, :payable_at, presence: true
    validates :void_reason, inclusion: { in: VOID_REASONS }, allow_nil: true

    STATES.each do |name|
      scope name, -> { where(state: name) }
      define_method("#{name}?") { state == name }
    end
    # Sales that count: everything but void.
    scope :counted, -> { where.not(state: 'void') }

    # Makes pending earnings whose hold has passed payable. Returns how many changed.
    def self.sweep!(now: Time.current)
      pending.where('payable_at <= ?', now).update_all(state: 'payable', updated_at: now)
    end

    def self.amount_for(gross, bps)
      (gross.to_d * bps.to_i / 10_000).round(2)
    end

    # gross less what was refunded.
    def net_gross
      gross.to_d - refunded_gross.to_d
    end

    # Voids a pending or payable earning by hand (a single guarded update, so it never races a
    # payout). Returns false when it was paid or already void.
    def void_by_admin!(now: Time.current)
      changed = self.class.where(id: id, state: %w[pending payable])
                    .update_all(state: 'void', void_reason: 'admin', updated_at: now)
      reload
      changed == 1
    end

    def order_masked
      Creators.mask_order_number(order&.number)
    end
  end
end
