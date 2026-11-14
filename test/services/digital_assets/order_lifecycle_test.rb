require 'test_helper'
require 'minitest/mock'

# Orders grant, and cancels and refunds revoke, ownership of digital line items. Digital-only
# orders skip the delivery step; guests cannot check out digital items.
class DigitalAssets::OrderLifecycleTest < ActionDispatch::IntegrationTest
  ADDRESS = { firstname: 'A', lastname: 'B', address1: '1 Main St', city: 'Town', zipcode: '12345', phone: '5550100' }.freeze

  setup do
    @country = Spree::Country.create!(iso: 'ZZ', iso3: 'ZZZ', iso_name: 'TESTLAND', name: 'Testland',
                                      states_required: false, zipcode_required: false)
    zone = Spree::Zone.create!(name: "Everywhere #{SecureRandom.hex(2)}", kind: 'country')
    zone.zone_members.create!(zoneable: @country)
    Spree::StockLocation.create!(name: "Main #{SecureRandom.hex(2)}", propagate_all_variants: true,
                                 backorderable_default: false, active: true, country: @country)
    category = Spree::ShippingCategory.first_or_create!(name: 'Default')
    Spree::ShippingMethod.create!(name: 'Flat', display_on: 'both', shipping_categories: [category], zones: [zone],
                                  calculator: Spree::Calculator::Shipping::FlatRate.new)
    @payment_method = Spree::PaymentMethod::Check.create!(name: 'Check', active: true, display_on: 'both')
    @payment_method.stores << digital_store if @payment_method.respond_to?(:stores)

    @user = create(:user)
    @pack = published_asset(price: 10).variant
    @preset = published_asset(price: 5).variant
    @shirt = create(:digital_product, name: 'Shirt', price: 20).master
    @shirt.stock_items.each { |item| item.set_count_on_hand(10) }
  end

  def json
    JSON.parse(response.body)
  end

  # --- checkout rig over the v2 storefront API ---------------------------------------------

  def start_cart(user = @user)
    @headers = user ? auth(user) : {}
    post '/api/v2/storefront/cart', headers: @headers
    assert_response :success, response.body
    @number = json['data']['attributes']['number']
    @headers = @headers.merge('X-Spree-Order-Token' => json['data']['attributes']['token']) unless user
  end

  def order
    Spree::Order.find_by!(number: @number)
  end

  def add(variant, quantity = 1)
    post '/api/v2/storefront/cart/add_item', params: { variant_id: variant.id, quantity: quantity }, headers: @headers
    assert_response :success, response.body
  end

  def addresses(ship: true)
    address = ADDRESS.merge(country_id: @country.id)
    attrs = { email: @user&.email || 'guest@example.com', bill_address_attributes: address }
    attrs[:ship_address_attributes] = address if ship
    patch '/api/v2/storefront/checkout', headers: @headers, params: { order: attrs }
    assert_response :success, response.body
  end

  def next_step
    patch '/api/v2/storefront/checkout/next', headers: @headers
  end

  def pay_and_complete
    current = order
    current.payments.create!(payment_method: @payment_method, amount: current.total)
    patch '/api/v2/storefront/checkout/complete', headers: @headers
    assert_response :success, response.body
    assert order.completed?
    order
  end

  # A completed digital-only order for @user holding the given variants.
  def complete_digital_order(*variants)
    start_cart
    variants.each { |v| add(v) }
    addresses(ship: false)
    next_step
    assert_response :success, response.body
    next_step
    assert_response :success, response.body
    assert_equal 'payment', order.state
    pay_and_complete
  end

  def ownerships
    Spree::DigitalOwnership.where(user_id: @user.id)
  end

  def refund(order, amount)
    payment = order.payments.valid.first
    payment.capture! if payment.pending?
    Spree::Refund.create!(payment: payment, amount: amount, reason: Spree::RefundReason.first_or_create!(name: 'Return'))
  end

  # --- tests ---------------------------------------------------------------------------------

  test 'completing an order grants one ownership per digital line item' do
    complete_digital_order(@pack, @preset)

    assert_equal [@pack.id, @preset.id].sort, ownerships.active.pluck(:variant_id).sort
    assert(ownerships.all? { |o| o.source == 'order' && o.source_record == order })
  end

  test 're-running the granter creates no duplicates' do
    completed = complete_digital_order(@pack)
    3.times { DigitalAssets::OrderGranter.call(completed.reload) }
    assert_equal 1, ownerships.count

    # A state-machine re-run (an admin resuming a canceled order) leaves exactly one active row.
    completed.canceled_by(create(:user))
    completed.reload.resume!
    3.times { DigitalAssets::OrderGranter.call(completed.reload) }
    assert_equal 1, ownerships.active.count
    assert_equal [@pack.id], ownerships.active.pluck(:variant_id)
  end

  test 'resuming a canceled order through the state machine grants again' do
    completed = complete_digital_order(@pack)
    completed.canceled_by(create(:user))
    assert_equal 0, ownerships.active.count

    completed.reload.resume!
    assert_equal 'resumed', completed.reload.state
    assert_equal [@pack.id], ownerships.active.pluck(:variant_id)
    assert_equal 2, ownerships.count
  end

  test 'a grant failure (a database error) leaves the order complete' do
    start_cart
    add(@pack)
    addresses(ship: false)
    next_step
    next_step
    current = order
    current.payments.create!(payment_method: @payment_method, amount: current.total)
    failing = ->(**) { ActiveRecord::Base.connection.execute('SELECT * FROM digital_assets_missing_table') }
    Spree::DigitalOwnership.stub(:grant!, failing) do
      patch '/api/v2/storefront/checkout/complete', headers: @headers
    end
    assert_response :success, response.body
    assert order.completed?
    assert_equal 'complete', order.state
    assert_equal 0, ownerships.count
  end

  test 'a revoke failure in a refund keeps the refund' do
    completed = complete_digital_order(@pack)
    failing = ->(*, **) { ActiveRecord::Base.connection.execute('SELECT * FROM digital_assets_missing_table') }
    DigitalAssets::OrderRevoker.stub(:call, failing) { refund(completed, completed.total) }
    assert_equal 1, Spree::Refund.count
    assert ownerships.first.active?
  end

  test 'a zero-total digital order completes without payment and grants' do
    free = published_asset(price: 0).variant
    start_cart
    add(free)
    addresses(ship: false)
    # No payment and no confirmation step: advance goes all the way to complete.
    patch '/api/v2/storefront/checkout/advance', headers: @headers
    assert_response :success, response.body
    assert order.completed?
    assert_equal [free.id], ownerships.active.pluck(:variant_id)
  end

  test 'an order paid with store credit grants' do
    category = Spree::StoreCreditCategory.first_or_create!(name: 'Default')
    Spree::PaymentMethod::StoreCredit.first_or_create!(name: 'Store Credit', active: true, display_on: 'both')
    Spree::StoreCreditType.first_or_create!(name: 'Expiring', priority: 1)
    Spree::StoreCredit.create!(user: @user, amount: 50, category: category, created_by: @user, currency: 'USD')
    start_cart
    add(@pack)
    addresses(ship: false)
    next_step
    next_step
    assert_equal 'payment', order.state
    post '/api/v2/storefront/checkout/add_store_credit', headers: @headers
    assert_response :success, response.body
    patch '/api/v2/storefront/checkout/complete', headers: @headers
    assert_response :success, response.body
    assert order.completed?
    assert_equal [@pack.id], ownerships.active.pluck(:variant_id)
  end

  test 'a guest who reached address cannot add a digital item and go on' do
    start_cart(nil)
    add(@shirt)
    addresses
    next_step
    assert_equal 'address', order.state

    add(@pack)
    next_step
    assert_response :unprocessable_entity
    assert_equal 'digital_requires_account', json['error']
    assert_equal 'address', order.state

    patch '/api/v2/storefront/checkout/advance', headers: @headers
    refute %w[delivery payment confirm complete].include?(order.state)
  end

  test 'a guest at payment who adds a digital item gets no 500 and cannot complete' do
    start_cart(nil)
    add(@shirt)
    addresses
    3.times { next_step }
    assert_equal 'payment', order.state
    current = order
    current.payments.create!(payment_method: @payment_method, amount: current.total)

    post '/api/v2/storefront/cart/add_item', params: { variant_id: @pack.id, quantity: 1 }, headers: @headers
    assert_response :success, response.body
    assert_equal 'cart', order.state

    patch '/api/v2/storefront/checkout/complete', headers: @headers
    assert_response :unprocessable_entity
    refute order.completed?
    next_step
    assert_response :unprocessable_entity
    assert_equal 'digital_requires_account', json['error']
    assert_equal 0, Spree::DigitalOwnership.count
  end

  test 'a guest order holding a digital item cannot be completed from payment' do
    start_cart(nil)
    add(@shirt)
    addresses
    3.times { next_step }
    # Slipped in without the cart service (no checkout restart).
    order.line_items.create!(variant: @pack, quantity: 1, price: 10)
    current = order
    current.update_with_updater!
    current.payments.create!(payment_method: @payment_method, amount: current.total)
    patch '/api/v2/storefront/checkout/complete', headers: @headers
    assert_response :unprocessable_entity
    assert_equal 'digital_requires_account', json['error']
    refute order.completed?
    assert_equal %w[checkout], order.payments.map(&:state)
  end

  test 'the granter does nothing for an incomplete order or one without a user' do
    start_cart
    add(@pack)
    DigitalAssets::OrderGranter.call(order)
    assert_equal 0, Spree::DigitalOwnership.count

    order.update_columns(user_id: nil)
    DigitalAssets::OrderGranter.call(order)
    assert_equal 0, Spree::DigitalOwnership.count
  end

  test 'cancel revokes with reason "order_canceled"' do
    completed = complete_digital_order(@pack, @preset)
    completed.canceled_by(create(:user))

    assert_equal 'canceled', completed.reload.state
    assert_equal 0, ownerships.active.count
    assert_equal %w[order_canceled order_canceled], ownerships.pluck(:revoke_reason)
  end

  test 'cancel leaves ownership from another source alone' do
    granted = Spree::DigitalOwnership.grant!(user: @user, variant: @pack, source: 'grant')
    completed = complete_digital_order(@pack)
    completed.canceled_by(create(:user))
    assert granted.reload.active?
  end

  test 'refund covering a line item revokes that item only' do
    completed = complete_digital_order(@pack, @preset)
    refund(completed, 5)

    assert ownerships.find_by(variant_id: @pack.id).active?
    revoked = ownerships.find_by(variant_id: @preset.id)
    refute revoked.active?
    assert_equal 'refunded', revoked.revoke_reason
  end

  test 'a partial refund that matches no line item revokes nothing; a full refund revokes all' do
    completed = complete_digital_order(@pack, @preset)
    refund(completed, 3)
    assert_equal 2, ownerships.active.count

    refund(completed, completed.total - 3)
    assert_equal 0, ownerships.active.count
  end

  test 'digital-only order skips delivery step and completes with only billing address' do
    start_cart
    add(@pack)
    refute order.delivery_required?
    refute_includes order.checkout_steps, 'delivery'

    addresses(ship: false)
    next_step
    assert_response :success, response.body
    assert_equal 'address', order.state
    next_step
    assert_response :success, response.body
    assert_equal 'payment', order.state

    completed = pay_and_complete
    assert completed.bill_address.present?
    assert_nil completed.ship_address
    assert_empty completed.shipments
    assert_equal 0, completed.ship_total
    assert ownerships.active.exists?(variant_id: @pack.id)
  end

  test 'a digital variant with no stock can still be bought' do
    @pack.stock_items.each { |item| item.set_count_on_hand(0) }
    @pack.update!(track_inventory: true)
    complete_digital_order(@pack)
    assert ownerships.active.exists?(variant_id: @pack.id)
  end

  test 'mixed order keeps delivery' do
    start_cart
    add(@pack)
    add(@shirt)
    assert order.delivery_required?
    assert_includes order.checkout_steps, 'delivery'

    addresses
    3.times do |step|
      next_step
      assert_response :success, response.body
      assert_equal %w[address delivery payment][step], order.state
    end
    completed = pay_and_complete
    assert_equal 1, completed.shipments.count
    assert_equal [@pack.id], ownerships.active.pluck(:variant_id)
  end

  test 'guest order with a digital item cannot leave cart: 422 digital_requires_account' do
    start_cart(nil)
    add(@pack)
    add(@shirt)
    addresses

    next_step
    assert_response :unprocessable_entity
    assert_equal 'digital_requires_account', json['error']
    assert_equal 'cart', order.state

    patch '/api/v2/storefront/checkout/advance', headers: @headers
    assert_equal 'cart', order.state
  end

  test 'guest physical-only order is unaffected' do
    start_cart(nil)
    add(@shirt)
    addresses
    next_step
    assert_response :success, response.body
    assert_equal 'address', order.state
  end

  test 'a draft asset does not make a variant digital' do
    draft = Spree::DigitalAsset.create!(variant: @shirt, kind: 'pack')
    assert draft.draft?
    start_cart(nil)
    add(@shirt)
    assert order.delivery_required?
    addresses
    next_step
    assert_response :success, response.body
  end
end
