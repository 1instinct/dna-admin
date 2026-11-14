require 'test_helper'
require 'minitest/mock'

# Creator earnings follow the order: completion records one per creator line item, refunds and
# cancels void them, a resume brings them back, and the sweep makes them payable after the hold.
class Creators::EarningsLifecycleTest < ActiveSupport::TestCase
  setup do
    digital_store
    Spree::StockLocation.first || Spree::StockLocation.create!(name: 'Main', backorderable_default: true,
                                                                propagate_all_variants: true)
    @creator = creator_user
    @account = Spree::CreatorAccount.find_by!(user_id: @creator.id)
    @pack = approved_creator_product(@creator, price: 10)
    @preset = approved_creator_product(@creator, price: 5)
    @shirt = create(:digital_product, name: 'Shirt', price: 20)
    @shirt.master.stock_items.each { |item| item.update!(backorderable: true) }
    @buyer = create(:user)
  end

  def earnings
    Spree::CreatorEarning.where(creator_account_id: @account.id)
  end

  test 'complete creates one earning per creator line item at share_bps' do
    order = complete_order!(cart_order(@buyer, [@pack, 2], [@preset, 1], [@shirt, 1]))

    assert_equal 2, earnings.count
    pack = earnings.find_by!(line_item_id: order.line_items.find_by!(variant_id: @pack.master.id).id)
    assert_equal 20.0, pack.gross.to_f
    assert_equal 7000, pack.share_bps
    assert_equal 14.0, pack.amount.to_f
    assert_equal 'USD', pack.currency
    assert_equal 'pending', pack.state
    assert_equal order.id, pack.order_id
    assert_in_delta (order.completed_at + 14.days).to_f, pack.payable_at.to_f, 1
    assert_equal 3.5, earnings.find_by!(line_item_id: order.line_items.find_by!(variant_id: @preset.master.id).id).amount.to_f
  end

  test 'the share is the account share at completion' do
    @account.update!(revenue_share_bps: 8000)
    complete_order!(cart_order(@buyer, [@pack, 1]))
    earning = earnings.first
    assert_equal 8000, earning.share_bps
    assert_equal 8.0, earning.amount.to_f
  end

  test 're-run none' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    3.times { Creators::EarningsRecorder.call(order.reload) }
    assert_equal 2, earnings.count

    order.canceled_by(admin_user)
    order.reload.resume!
    Creators::EarningsRecorder.call(order.reload)
    assert_equal 2, earnings.count
    assert_equal %w[pending pending], earnings.pluck(:state)
  end

  test 'gross deducts item and order promotions' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    earnings.delete_all
    pack_item = order.line_items.find_by!(variant_id: @pack.master.id)
    pack_item.update_columns(promo_total: -2)
    promotion = Spree::Promotion.create!(name: 'Order off')
    action = Spree::Promotion::Actions::CreateAdjustment.create!(promotion: promotion,
                                                                  calculator: Spree::Calculator::FlatRate.new)
    adjustment = order.adjustments.create!(order: order, source: action, amount: -3, label: 'Order off', eligible: true)
    adjustment.update_columns(amount: -3) # Spree recomputes it from the calculator on save

    Creators::EarningsRecorder.call(order.reload)
    # item total 15; the pack's 10 carries -2 of its own and 10/15 of the order's -3.
    assert_equal 6.0, earnings.find_by!(line_item_id: pack_item.id).gross.to_f
    assert_equal 4.2, earnings.find_by!(line_item_id: pack_item.id).amount.to_f
    assert_equal 4.0, earnings.where.not(line_item_id: pack_item.id).first.gross.to_f
  end

  test 'refund covering a line item voids that earning only' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    refund(order, 5)
    assert_equal 'void', earning_for(order, @preset).state
    assert_equal 'pending', earning_for(order, @pack).state
  end

  test 'partial refund then cancel voids everything' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    refund(order, 3)
    assert_equal %w[pending pending], earnings.pluck(:state)

    order.reload.canceled_by(admin_user)
    assert_equal %w[void void], earnings.pluck(:state)
  end

  test 'full refund voids all earnings' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    refund(order, order.total)
    assert_equal %w[void void], earnings.pluck(:state)
  end

  test 'resume brings voided earnings back; paid earnings never change' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    earning_for(order, @pack).update!(state: 'paid')
    order.canceled_by(admin_user)
    assert_equal 'paid', earning_for(order, @pack).state
    assert_equal 'void', earning_for(order, @preset).state

    order.reload.resume!
    assert_equal 'paid', earning_for(order, @pack).state
    assert_equal 'pending', earning_for(order, @preset).state
  end

  test 'refund, then cancel, then resume brings back only the cancel-voided earning' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    refund(order, 5)
    assert_equal 'refund', earning_for(order, @preset).void_reason

    order.reload.canceled_by(admin_user)
    assert_equal 'cancel', earning_for(order, @pack).void_reason
    assert_equal 'refund', earning_for(order, @preset).void_reason

    order.reload.resume!
    assert_equal 'pending', earning_for(order, @pack).state
    assert_nil earning_for(order, @pack).void_reason
    assert_equal 'void', earning_for(order, @preset).state
    assert_equal 'refund', earning_for(order, @preset).void_reason
  end

  test 'multi-creator order: a matching refund voids only that line item' do
    other = creator_user
    theirs = approved_creator_product(other, price: 7)
    order = complete_order!(cart_order(@buyer, [@pack, 1], [theirs, 1]))
    refund(order, 7)

    assert_equal 'void', Spree::CreatorEarning.find_by!(line_item_id: order.line_items.find_by!(variant_id: theirs.master.id).id).state
    assert_equal 'pending', earning_for(order, @pack).state
  end

  test 'a refund matching several equal-price line items voids nothing and is logged' do
    twin = approved_creator_product(@creator, price: 5)
    order = complete_order!(cart_order(@buyer, [@preset, 1], [twin, 1], [@pack, 1]))
    logged = capture_log { refund(order, 5) }

    assert_equal %w[pending pending pending], earnings.order(:id).pluck(:state)
    assert_equal [0.0], earnings.distinct.pluck(:refunded_gross).map(&:to_f)
    assert_match(/matches 2 line items/, logged)
  end

  test 'a partial refund matching no line item is prorated over the earnings' do
    order = complete_order!(cart_order(@buyer, [@pack, 1], [@preset, 1]))
    refund(order, 3) # a fifth of the 15.00 order

    pack = earning_for(order, @pack)
    assert_equal 'pending', pack.state
    assert_equal 2.0, pack.refunded_gross.to_f
    assert_equal 5.6, pack.amount.to_f # (10 - 2) * 70%
    assert_equal 1.0, earning_for(order, @preset).refunded_gross.to_f
    assert_equal 2.8, earning_for(order, @preset).amount.to_f
  end

  test '1 of 3 returned through a reimbursement takes a third off the earning' do
    order = complete_order!(cart_order(@buyer, [@pack, 3]))
    line_item = order.line_items.first
    payment = order.payments.valid.first
    unit = Struct.new(:line_item_id, :quantity).new(line_item.id, 1)
    reimbursement = Struct.new(:id, :return_items, :refunds).new(42, [Struct.new(:inventory_unit).new(unit)], [])
    refund = Struct.new(:id, :payment, :amount, :reimbursement).new(7, payment, 10, reimbursement)
    reimbursement.refunds << refund

    Creators::EarningsRecorder.for_refund(refund)
    earning = earning_for(order, @pack)
    assert_equal 'pending', earning.state
    assert_equal 10.0, earning.refunded_gross.to_f
    assert_equal 14.0, earning.amount.to_f # (30 - 10) * 70%
  end

  test 'a creator buying their own product earns nothing' do
    complete_order!(cart_order(@creator, [@pack, 1]))
    assert_equal 0, earnings.count
  end

  test 'store products and creators without an account earn nothing' do
    stray_creator = creator_user
    stray = approved_creator_product(stray_creator, price: 3)
    Spree::CreatorAccount.where(user_id: stray_creator.id).delete_all
    complete_order!(cart_order(@buyer, [@shirt, 1], [stray, 1]))
    assert_equal 0, Spree::CreatorEarning.count
  end

  test 'a failing recorder never breaks checkout' do
    Creators::EarningsRecorder.stub(:new, ->(*) { raise 'boom' }) do
      order = complete_order!(cart_order(@buyer, [@pack, 1]))
      assert order.reload.complete?
      assert order.canceled_by(admin_user)
    end
    assert_equal 0, earnings.count
  end

  test 'sweep pending to payable after hold' do
    due = create(:creator_earning, creator_account: @account, payable_at: 1.minute.ago)
    later = create(:creator_earning, creator_account: @account, payable_at: 1.day.from_now)
    void = create(:creator_earning, creator_account: @account, payable_at: 1.day.ago, state: 'void')

    assert_equal 1, Spree::CreatorEarning.sweep!
    assert_equal 'payable', due.reload.state
    assert_equal 'pending', later.reload.state
    assert_equal 'void', void.reload.state
  end

  test 'payout marks payable earnings paid' do
    payable = create(:creator_earning, creator_account: @account, state: 'payable', amount: 7)
    other = create(:creator_earning, creator_account: @account, state: 'payable', amount: 3.5)
    pending = create(:creator_earning, creator_account: @account, state: 'pending', amount: 1)

    payout = Creators::Payouts.create!(account: @account, reference: 'BANK-1', note: 'Nov', currency: 'USD')
    assert_equal 10.5, payout.amount.to_f
    assert_equal 'BANK-1', payout.reference
    assert payout.paid_at
    assert_equal %w[paid paid], [payable, other].map { |e| e.reload.state }
    assert_equal [payout.id, payout.id], [payable, other].map(&:creator_payout_id)
    assert_equal 'pending', pending.reload.state

    assert_raises(Creators::Payouts::Error) { Creators::Payouts.create!(account: @account, reference: 'X', currency: 'USD') }
    assert_raises(Creators::Payouts::Error) do
      create(:creator_earning, creator_account: @account, state: 'payable')
      Creators::Payouts.create!(account: @account, reference: ' ', currency: 'USD')
    end
  end

  private

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    original = Rails.logger
    Rails.logger = logger
    yield
    io.string
  ensure
    Rails.logger = original
  end

  def earning_for(order, product)
    earnings.find_by!(line_item_id: order.line_items.find_by!(variant_id: product.master.id).id)
  end

  def refund(order, amount)
    payment = order.payments.valid.first
    payment.capture! if payment.pending?
    Spree::Refund.create!(payment: payment, amount: amount, reason: Spree::RefundReason.first_or_create!(name: 'Return'))
  end
end
