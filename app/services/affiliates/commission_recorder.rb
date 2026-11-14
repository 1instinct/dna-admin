module Affiliates
  # Keeps an attributed order's commission in step with the order. Safe to run any number of times.
  #
  # - Completion creates one pending commission, when the order's affiliate is approved and the
  #   order isn't the affiliate's own: base_amount is the item total after promotions, without
  #   shipping or tax; approvable_at is completion + Affiliates.config.hold_days.
  # - A refund takes the refunded amount off the base (a refund doesn't say what it covers, so
  #   shipping and tax refunds count too). A full refund, or a cancel, makes it void.
  # - A resume (revive: true) brings a void commission back to pending.
  # - A paid commission is never changed. A void one only changes on a resume.
  #
  # Errors are logged and swallowed, inside a savepoint: commission bookkeeping never fails checkout.
  class CommissionRecorder
    def self.call(order, revive: false, now: Time.current)
      new(order, revive: revive, now: now).call
    end

    attr_reader :order, :revive, :now

    def initialize(order, revive:, now:)
      @order = order
      @revive = revive
      @now = now
    end

    def call
      return if order.nil? || order.affiliate_account_id.nil?

      AffiliateCommission.transaction(requires_new: true) do
        commission = AffiliateCommission.lock.find_by(order_id: order.id)
        commission ? update(commission) : create
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

    def refunded
      Spree::Refund.joins(:payment).where(spree_payments: { order_id: order.id }).sum(:amount).to_d
    end

    private

    def create
      return unless order.complete? && order.completed_at

      account = order.affiliate_account
      return unless account&.earning?
      return if Attribution.self_referral?(order, account)

      base = net_base
      return if base <= 0

      bps = account.effective_commission_bps
      AffiliateCommission.create!(
        affiliate_account: account, order: order, base_amount: base, commission_bps: bps,
        amount: AffiliateCommission.amount_for(base, bps), currency: order.currency, state: 'pending',
        approvable_at: order.completed_at + Affiliates.config.hold_days.days
      )
    end

    def update(commission)
      return commission if commission.paid?
      return commission if commission.void? && !revive

      base = net_base
      attrs = { base_amount: base, amount: AffiliateCommission.amount_for(base, commission.commission_bps) }
      attrs[:state] = if order.canceled? || base <= 0 || fully_refunded?
                        'void'
                      elsif commission.void?
                        'pending'
                      else
                        commission.state
                      end
      commission.update!(attrs)
      commission
    end

    def net_base
      [gross_base - refunded, 0.to_d].max.round(2)
    end

    def fully_refunded?
      order.total.to_d.positive? && refunded >= order.total.to_d
    end
  end
end
