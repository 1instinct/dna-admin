module Creators
  # Keeps an order's creator earnings in step with the order. Safe to run any number of times.
  #
  # - Completion: one pending earning per line item of a creator product whose creator has an
  #   account, at the account's share then: gross = the line item amount after its own promotions
  #   and its share (by amount) of the order's promotions; payable_at = completed_at + hold_days.
  #   A line item with nothing to share (gross 0, e.g. a free claimable item) earns nothing.
  # - Cancel: every earning of the order goes void. Resume (revive: true): void earnings come
  #   back (pending, or payable when the hold has passed).
  # - Refund (for_refund): voids the earnings of the line items the refund covers, the way
  #   DigitalAssets::OrderRevoker decides it: the returned units of a reimbursement; every line item
  #   once refunds reach the order total; else the first counted earning whose line item amount
  #   (or final amount) equals the refund.
  # - Paid earnings never change.
  #
  # Runs in a savepoint and logs and swallows its errors: earnings bookkeeping never fails
  # checkout, a cancel or a refund.
  class EarningsRecorder
    def self.call(order, revive: false, now: Time.current)
      safely(order) { new(order, now: now).record(revive: revive) }
    end

    def self.for_refund(refund, now: Time.current)
      order = refund&.payment && Spree::Order.find_by(id: refund.payment.order_id)
      safely(order) { new(order, now: now).void_refunded(refund) }
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
          earning.update!(state: 'void') unless earning.void?
          earning
        elsif revive && earning.void?
          earning.update!(state: earning.payable_at <= now ? 'payable' : 'pending')
          earning
        else
          earning
        end
      end.compact
    end

    def void_refunded(refund)
      ids = refunded_line_item_ids(refund)
      Spree::CreatorEarning.where(order_id: order.id, line_item_id: ids, state: %w[pending payable])
                           .update_all(state: 'void', updated_at: now)
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

    # [[line_item, creator account]] for line items of creator products.
    def creator_line_items
      items = order.line_items.includes(variant: :product).to_a
      creator_ids = items.map { |li| li.variant&.product&.creator_id }.compact.uniq
      return [] if creator_ids.empty?

      accounts = Spree::CreatorAccount.where(user_id: creator_ids).index_by(&:user_id)
      items.filter_map do |line_item|
        account = accounts[line_item.variant&.product&.creator_id]
        [line_item, account] if account
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

    def refunded_line_item_ids(refund)
      if refund.respond_to?(:reimbursement) && refund.reimbursement
        return refund.reimbursement.return_items.map { |item| item.inventory_unit&.line_item_id }.compact.uniq
      end
      return order.line_items.pluck(:id) if order.refunds.sum(:amount) >= order.total

      counted = Spree::CreatorEarning.counted.where(order_id: order.id).pluck(:line_item_id)
      match = order.line_items.detect do |line_item|
        counted.include?(line_item.id) &&
          [line_item.amount, line_item.final_amount].any? { |amount| amount.to_d == refund.amount.to_d }
      end
      match ? [match.id] : []
    end
  end
end
