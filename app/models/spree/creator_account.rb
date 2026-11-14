# An approved creator: their share of each sale (revenue_share_bps, basis points), where to pay
# them, and whether they may sell (active) or not (suspended). Earnings and payouts hang off it.
module Spree
  class CreatorAccount < Spree::Base
    STATUSES = %w[active suspended].freeze

    self.table_name = 'spree_creator_accounts'

    belongs_to :user, class_name: Spree.user_class.to_s

    scope :active, -> { where(status: 'active') }

    before_validation { self.revenue_share_bps ||= Creators.config.default_share_bps }
    validates :user_id, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :revenue_share_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0,
                                                  less_than_or_equal_to: 10_000 }
    validates :payout_email, length: { maximum: 255 },
                             format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
    validates :payout_notes, length: { maximum: 2000 }

    def active?
      status == 'active'
    end

    def suspended?
      status == 'suspended'
    end
  end
end
