module Creators
  # Keeps an order's creator earnings in step with the order. Safe to run any number of times.
  #
  # - Completion: one pending earning per line item of a creator product whose creator has an
  #   account, at the account's share then: gross = the line item amount after its own promotions
  #   and its share (by amount) of the order's promotions; payable_at = completed_at + hold_days.
  #   A line item with nothing to share (gross 0, e.g. a free claimable item) earns nothing, and a
  #   creator buying their own product earns nothing.
  # - Cancel: every unpaid earning of the order goes void with void_reason "cancel". Resume
  #   (revive: true) brings back only the cancel-voided ones (pending, or payable when the hold has
  #   passed); an earning voided by a refund or an admin stays void.
  # - Refund (for_refund), in step with DigitalAssets::OrderRevoker:
  #   - through a reimbursement (on its first refund only): each returned line item loses the
  #     returned units' share of its gross (refunded_gross); a fully returned one goes void;
  #   - once the order's refunds reach its total: every earning goes void;
  #   - else, when the amount equals exactly one line item's amount (or final amount): that line
  #     item's earning goes void (a store item matching voids nothing);
  #   - else, when it equals more than one: nothing changes and it is logged for an admin;
  #   - else (a partial refund matching no line item): every earning loses refund / order total of
  #     its gross.
  #   amount is recomputed from gross - refunded_gross; void_reason is "refund".
  # - Paid earnings never change.
  #
  # Runs in a savepoint and logs and swallows its errors: earnings bookkeeping never fails
  # checkout, a cancel or a refund.
  class EarningsRecorder
    OPEN = %w[pending payable].freeze

    def self.call(order, revive: false, now: Time.current)
      safely(order) { new(order, now: now).record(revive: revive) }
    end

    def self.for_refund(refund, now: Time.current)
      order = refund&.payment && Spree::Order.find_by(id: refund.payment.order_id)
      safely(order) { new(order, now: now).apply_refund(refund) }
    end

    def self.safely(order)
      return if order.nil?

      Spree::CreatorEarning.transaction(requires_new: true) { yield }
    rescue StandardError => e
      Rails.logger.error("[creators] earnings for order #{order&.id} failed: #{e.class}: #{e.message}")
      nil
    end

    attr_reader :order, :now

    def initialize(order, now:)
      @order = order
      @now = now
    end

    def record(revive: false)
      return [] unless order.completed_at

      creator_line_items.map do |line_item, account|
        earning = Spree::CreatorEarning.lock.find_by(line_item_id: line_item.id)
        if earning.nil?
          create(line_item, account) unless order.canceled?
        elsif earning.paid?
          earning
        elsif order.canceled?
          earning.update!(state: 'void', void_reason: 'cancel') unless earning.void?
          earning
        elsif revive && earning.void? && earning.void_reason == 'cancel'
          earning.update!(state: earning.payable_at <= now ? 'payable' : 'pending', void_reason: nil)
          earning
        else
          earning
        end
      end.compact
    end

    def apply_refund(refund)
      reimbursement = refund.respond_to?(:reimbursement) ? refund.reimbursement : nil
      return apply_returns(reimbursement) if reimbursement && first_refund_of?(reimbursement, refund)
      return [] if reimbursement
      return void(open_earnings) if order.refunds.sum(:amount) >= order.total

      matches = order.line_items.select do |line_item|
        [line_item.amount, line_item.final_amount].any? { |amount| amount.to_d == refund.amount.to_d }
      end
      if matches.size > 1
        Rails.logger.warn("[creators] refund #{refund.id} on order #{order.number} matches #{matches.size} " \
                          'line items; no earning changed, adjust by hand if needed')
        return []
      end
      return void(open_earnings.where(line_item_id: matches.first.id)) if matches.one?

      prorate(refund.amount.to_d / order.total.to_d) if order.total.to_d.positive?
    end

    # The line item's amount after its own promotions and its share of the order's promotions.
    def gross_for(line_item)
      amount = line_item.amount.to_d
      own = line_item.promo_total.to_d
      item_total = order.line_items.sum(&:amount).to_d
      order_promos = Spree::Adjustment.where(adjustable: order, source_type: 'Spree::PromotionAction', eligible: true)
                                      .sum(:amount).to_d
      share = item_total.positive? ? order_promos * amount / item_total : 0
      [amount + own + share, 0.to_d].max.round(2)
    end

    private

    # [[line_item, creator account]] for line items of creator products sold to someone else.
    def creator_line_items
      items = order.line_items.includes(variant: :product).to_a
      creator_ids = items.map { |li| li.variant&.product&.creator_id }.compact.uniq
      return [] if creator_ids.empty?

      accounts = Spree::CreatorAccount.where(user_id: creator_ids).index_by(&:user_id)
      items.filter_map do |line_item|
        account = accounts[line_item.variant&.product&.creator_id]
        [line_item, account] if account && account.user_id != order.user_id
      end
    end

    def create(line_item, account)
      gross = gross_for(line_item)
      return if gross <= 0

      bps = account.revenue_share_bps
      Spree::CreatorEarning.create!(
        creator_account: account, order_id: order.id, line_item_id: line_item.id, gross: gross, share_bps: bps,
        amount: Spree::CreatorEarning.amount_for(gross, bps), currency: line_item.currency || order.currency,
        state: 'pending', payable_at: order.completed_at + Creators.config.hold_days.days
      )
    end

    def open_earnings
      Spree::CreatorEarning.where(order_id: order.id, state: OPEN)
    end

    def void(scope)
      scope.update_all(state: 'void', void_reason: 'refund', updated_at: now)
    end

    # A reimbursement can pay out in several refunds; its returns are applied once, on the first.
    def first_refund_of?(reimbursement, refund)
      refunds = reimbursement.refunds
      refunds = refunds.reload if refunds.respond_to?(:reload)
      first = Array(refunds).map(&:id).compact.min
      first.nil? || first == refund.id
    end

    def apply_returns(reimbursement)
      units = Hash.new(0)
      reimbursement.return_items.each do |item|
        unit = item.inventory_unit
        units[unit.line_item_id] += (unit.respond_to?(:quantity) && unit.quantity) || 1 if unit&.line_item_id
      end
      quantities = order.line_items.where(id: units.keys).pluck(:id, :quantity).to_h
      open_earnings.where(line_item_id: units.keys).lock.map do |earning|
        quantity = quantities[earning.line_item_id].to_i
        reduce(earning, quantity.positive? ? units[earning.line_item_id].to_d / quantity : 1)
      end
    end

    def prorate(fraction)
      open_earnings.lock.map { |earning| reduce(earning, fraction) }
    end

    def reduce(earning, fraction)
      gross = earning.gross.to_d
      refunded = [earning.refunded_gross.to_d + (gross * [fraction, 1].min).round(2), gross].min
      net = gross - refunded
      if net <= 0
        earning.update!(state: 'void', void_reason: 'refund', refunded_gross: gross)
      else
        earning.update!(refunded_gross: refunded, amount: Spree::CreatorEarning.amount_for(net, earning.share_bps))
      end
      earning
    end
  end
end
