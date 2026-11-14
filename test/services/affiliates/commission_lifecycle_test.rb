require 'test_helper'
require 'minitest/mock'

# Order completion, refunds, cancel and resume drive the affiliate commission.
class Affiliates::CommissionLifecycleTest < ActiveSupport::TestCase
  setup do
    affiliate_store
    @affiliate = approved_affiliate(code: 'life-code')
    @admin = create(:user)
  end

  teardown { Affiliates.reset_config! }

  def attributed_cart(products: nil, user: nil)
    order = cart_order(products: products || [affiliate_product(price: 40), affiliate_product(price: 60)], user: user,
                       email: user&.email || 'buyer@example.com')
    assert Affiliates::Attribution.attach(order, @affiliate)
    order
  end

  # An order-level promotion adjustment. It is closed, so the order updater keeps its amount
  # instead of recomputing it from the calculator.
  def add_order_promotion(order, amount)
    promotion = Spree::Promotion.create!(name: "Promo #{SecureRandom.hex(2)}")
    action = Spree::Promotion::Actions::CreateAdjustment.create!(promotion: promotion,
                                                                 calculator: Spree::Calculator::FlatRate.new)
    order.adjustments.create!(order: order, adjustable: order, source: action, amount: -amount, label: 'Promo',
                              eligible: true, state: 'closed')
    order.update_with_updater!
  end

  def add_shipment(order, cost)
    order.shipments.create!(stock_location: Spree::StockLocation.first, cost: cost, state: 'pending')
    order.update_with_updater!
  end

  def capture_and_refund(order, amount)
    payment = order.payments.valid.first
    payment.capture! if payment.pending?
    reason = Spree::RefundReason.first || Spree::RefundReason.create!(name: 'Return')
    Spree::Refund.create!(payment: payment.reload, amount: amount, reason: reason)
    order.reload
  end

  test 'complete creates one pending commission on item_total after promos excl shipping/tax' do
    order = attributed_cart
    add_order_promotion(order, 10)
    add_shipment(order, 7)
    assert_equal(-10, order.reload.promo_total.to_i, 'the promotion applied')
    assert_equal 97, order.total.to_i, 'items 100, promotion -10, shipping 7'

    order = complete_order!(order)

    commission = AffiliateCommission.find_by!(order_id: order.id)
    assert_equal 'pending', commission.state
    assert_equal 90, commission.base_amount.to_i
    assert_equal 1000, commission.commission_bps
    assert_equal 9.0, commission.amount.to_f
    assert_equal 'USD', commission.currency
    assert_equal @affiliate, commission.affiliate_account
    assert_in_delta (order.completed_at + 30.days).to_i, commission.approvable_at.to_i, 2
  end

  test 'commission uses the account override and the configured hold' do
    @affiliate.update!(commission_bps: 2500)
    Affiliates.config.hold_days = 7
    order = complete_order!(attributed_cart)
    commission = order.affiliate_commission
    assert_equal 2500, commission.commission_bps
    assert_equal 25.0, commission.amount.to_f
    assert_in_delta (order.completed_at + 7.days).to_i, commission.approvable_at.to_i, 2
  end

  test 're-run creates none' do
    order = complete_order!(attributed_cart)
    assert_equal 1, AffiliateCommission.where(order_id: order.id).count

    order.finalize!
    Affiliates::CommissionRecorder.call(order)
    Affiliates::CommissionRecorder.call(order.reload)
    assert_equal 1, AffiliateCommission.where(order_id: order.id).count
    assert_equal 10.0, order.affiliate_commission.amount.to_f
  end

  test 'partial refund reduces base_amount and amount; cancel voids' do
    order = complete_order!(attributed_cart)
    capture_and_refund(order, 30)

    commission = order.affiliate_commission.reload
    assert_equal 70, commission.base_amount.to_i
    assert_equal 7.0, commission.amount.to_f
    assert_equal 'pending', commission.state

    order.reload.canceled_by(@admin)
    assert_equal 'canceled', order.reload.state
    assert_equal 'void', commission.reload.state
    assert_equal 1, AffiliateCommission.where(order_id: order.id).count
  end

  test 'a full refund voids' do
    order = complete_order!(attributed_cart)
    capture_and_refund(order, order.total)
    assert_equal 'void', order.affiliate_commission.reload.state
  end

  test 'resume after cancel reinstates the same commission' do
    order = complete_order!(attributed_cart)
    order.canceled_by(@admin)
    assert_equal 'void', order.affiliate_commission.reload.state

    order.reload.resume!
    assert_equal 'resumed', order.reload.state
    assert_equal 1, AffiliateCommission.where(order_id: order.id).count
    assert_equal 'pending', order.affiliate_commission.reload.state
  end

  test 'a paid commission is never changed by a refund or a cancel' do
    order = complete_order!(attributed_cart)
    order.affiliate_commission.update!(state: 'paid')
    capture_and_refund(order, 30)
    order.reload.canceled_by(@admin)
    commission = order.affiliate_commission.reload
    assert_equal 'paid', commission.state
    assert_equal 100, commission.base_amount.to_i
  end

  test 'an admin void survives a later refund' do
    order = complete_order!(attributed_cart)
    order.affiliate_commission.update!(state: 'void')
    capture_and_refund(order, 10)
    assert_equal 'void', order.affiliate_commission.reload.state
  end

  test 'suspended affiliate at completion earns nothing' do
    order = attributed_cart
    @affiliate.update!(status: 'suspended')
    complete_order!(order)
    assert_equal 0, AffiliateCommission.count
  end

  test 'the affiliate\'s own order earns nothing even when attributed' do
    order = cart_order(user: @affiliate.user, email: @affiliate.user.email)
    order.update_columns(affiliate_account_id: @affiliate.id, affiliate_attributed_at: Time.current)
    complete_order!(order)
    assert_equal 0, AffiliateCommission.count
  end

  test 'an order without an affiliate earns nothing' do
    complete_order!(cart_order)
    assert_equal 0, AffiliateCommission.count
  end

  test 'a recorder failure never breaks checkout' do
    order = attributed_cart
    AffiliateCommission.stub(:create!, ->(*) { raise ActiveRecord::StatementInvalid, 'boom' }) do
      complete_order!(order)
    end
    assert_equal 'complete', order.reload.state
    assert_equal 0, AffiliateCommission.count
  end
end
