module Affiliates
  # Keeps an attributed order's commission in step with the order. Safe to run any number of times.
  #
  # - Completion (create: true, from Order#finalize! only) creates one pending commission, when the
  #   order's affiliate is approved, the order isn't the affiliate's own and the attribution is
  #   within the account's cookie_days at completion: base_amount is the item total after
  #   promotions, without shipping or tax; approvable_at is completion + Affiliates.config.hold_days.
  #   Every other hook only updates an existing commission.
  # - Refunds and store-credit reimbursements take their amount off the base (they don't say what
  #   they cover, so shipping and tax count too). A full refund voids (void_reason "refunded"),
  #   a cancel voids ("order_canceled").
  # - A resume (revive: true) brings back a commission voided by the cancel, and only while the
  #   affiliate is still approved. Admin and refund voids stay void.
  # - A paid commission is never changed.
  #
  # Errors are logged and swallowed, inside a savepoint: commission bookkeeping never fails checkout.
  class CommissionRecorder
    def self.call(order, create: false, revive: false, now: Time.current)
      new(order, create: create, revive: revive, now: now).call
    end

    attr_reader :order, :create, :revive, :now

    def initialize(order, create:, revive:, now:)
      @order = order
      @create = create
      @revive = revive
      @now = now
    end

    def call
      return if order.nil? || order.affiliate_account_id.nil?

      AffiliateCommission.transaction(requires_new: true) do
        commission = AffiliateCommission.lock.find_by(order_id: order.id)
        if commission
          update(commission)
        elsif create
          create_commission
        end
      end
    rescue ActiveRecord::RecordNotUnique
      AffiliateCommission.find_by(order_id: order.id)
    rescue StandardError => e
      Rails.logger.error("[affiliates] commission for order #{order&.id} failed: #{e.class}: #{e.message}")
      nil
    end

    # The item total after item and order promotions, without shipping or tax, before refunds.
    def gross_base
      items = order.item_total.to_d
      item_promos = order.line_items.sum(:promo_total).to_d
      order_promos = order.adjustments.promotion.eligible.sum(:amount).to_d
      [items + item_promos + order_promos, 0.to_d].max.round(2)
    end

    # Refunds on the order's payments plus store credit given back through reimbursements.
    def refunded
      refunds = Spree::Refund.joins(:payment).where(spree_payments: { order_id: order.id }).sum(:amount).to_d
      credits = Spree::Reimbursement::Credit.joins(:reimbursement)
                                            .where(spree_reimbursements: { order_id: order.id }).sum(:amount).to_d
      refunds + credits
    end

    private

    def create_commission
      return unless order.complete? && order.completed_at

      account = order.affiliate_account
      return unless account&.earning?
      return if Attribution.self_referral?(order, account)
      return if attribution_expired?(account)

      base = net_base
      return if base <= 0

      bps = account.effective_commission_bps
      AffiliateCommission.create!(
        affiliate_account: account, order: order, base_amount: base, commission_bps: bps,
        amount: AffiliateCommission.amount_for(base, bps), currency: order.currency, state: 'pending',
        approvable_at: order.completed_at + Affiliates.config.hold_days.days
      )
    end

    def attribution_expired?(account)
      attributed_at = order.affiliate_attributed_at
      attributed_at.present? && attributed_at < order.completed_at - account.cookie_days.days
    end

    def update(commission)
      return commission if commission.paid?
      return commission if commission.void? && !revivable?(commission)

      base = net_base
      attrs = { base_amount: base, amount: AffiliateCommission.amount_for(base, commission.commission_bps) }
      if order.canceled?
        attrs.merge!(state: 'void', void_reason: commission.void? ? commission.void_reason : 'order_canceled')
      elsif base <= 0 || fully_refunded?
        attrs.merge!(state: 'void', void_reason: 'refunded')
      elsif commission.void?
        attrs.merge!(state: 'pending', void_reason: nil)
      end
      commission.update!(attrs)
      commission
    end

    def revivable?(commission)
      revive && commission.void_reason == 'order_canceled' && commission.affiliate_account&.earning?
    end

    def net_base
      [gross_base - refunded, 0.to_d].max.round(2)
    end

    def fully_refunded?
      order.total.to_d.positive? && refunded >= order.total.to_d
    end
  end
end
