require 'test_helper'

# Lines already in a cart when a product is hidden, and new lines for a hidden product.
class HiddenProductsCartTest < ActionDispatch::IntegrationTest
  ADDRESS = { firstname: 'A', lastname: 'B', address1: '1 Main St', city: 'Town', zipcode: '12345', phone: '5550100' }.freeze

  setup do
    @country = Spree::Country.create!(iso: 'ZZ', iso3: 'ZZZ', iso_name: 'TESTLAND', name: 'Testland',
                                      states_required: false, zipcode_required: false)
    zone = Spree::Zone.create!(name: "Everywhere #{SecureRandom.hex(2)}", kind: 'country')
    zone.zone_members.create!(zoneable: @country)
    @location = Spree::StockLocation.create!(name: "Main #{SecureRandom.hex(2)}", propagate_all_variants: true,
                                             backorderable_default: false, active: true, country: @country)
    category = Spree::ShippingCategory.first_or_create!(name: 'Default')
    @shipping_method = Spree::ShippingMethod.create!(name: 'Flat', display_on: 'both', shipping_categories: [category],
                                                     zones: [zone], calculator: Spree::Calculator::Shipping::FlatRate.new)
    @payment_method = Spree::PaymentMethod::Check.create!(name: 'Check', active: true, display_on: 'both')
    @payment_method.stores << media_store if @payment_method.respond_to?(:stores)

    build_catalog
    [@visible, @null_on, @future, @discontinued].each do |product|
      product.master.stock_items.each { |item| item.set_count_on_hand(10) }
    end
    @soon_hidden = media_product(name: 'Soon Hidden')
    @soon_hidden.master.stock_items.each { |item| item.set_count_on_hand(10) }
    media_image(@soon_hidden.master, ShopMediaTestHelper::PNG_BYTES, 'soon.png', 'image/png', width: 1, height: 1)

    post '/api/v2/storefront/cart'
    @token = media_json['data']['attributes']['token']
    @number = media_json['data']['attributes']['number']
  end

  def headers
    { 'X-Spree-Order-Token' => @token }
  end

  def order
    Spree::Order.find_by!(number: @number)
  end

  def add_item(variant, quantity = 1, query = '')
    post "/api/v2/storefront/cart/add_item#{query}", params: { variant_id: variant.id, quantity: quantity }, headers: headers
  end

  # A line added while the product was on sale, then the product is hidden.
  def line_on_hidden_product(quantity = 2)
    add_item(@soon_hidden.master, quantity)
    assert_response :success
    @soon_hidden.update!(available_on: nil)
    @soon_hidden.reload
    order.line_items.find_by!(variant_id: @soon_hidden.master.id)
  end

  def fill_in_addresses
    address = ADDRESS.merge(country_id: @country.id)
    patch '/api/v2/storefront/checkout', headers: headers,
                                         params: { order: { email: 'a@example.com', bill_address_attributes: address,
                                                            ship_address_attributes: address } }
    assert_response :success, response.body
  end

  def advance
    patch '/api/v2/storefront/checkout/advance', headers: headers
  end

  def pay
    current = order
    current.payments.create!(payment_method: @payment_method, amount: current.total)
  end

  def complete
    patch '/api/v2/storefront/checkout/complete', headers: headers
  end

  # --- existing lines ---------------------------------------------------------------------

  test 'cart with includes still shows the owner their own hidden line' do
    line = line_on_hidden_product

    get '/api/v2/storefront/cart?include=line_items,variants,variants.images', headers: headers
    assert_response :success
    assert_equal [line.id.to_s], media_json['data']['relationships']['line_items']['data'].map { |l| l['id'] }
    assert_equal 'Soon Hidden', media_json['included'].find { |i| i['type'] == 'line_item' }['attributes']['name']
    assert(media_json['included'].any? { |i| i['type'] == 'image' })

    get '/api/v2/storefront/cart?include=line_items,variants.product,variants.product.images', headers: headers
    assert_response :success
    assert(media_json['included'].any? { |i| i['type'] == 'product' && i['attributes']['slug'] == @soon_hidden.slug })
  end

  test 'a cart holding a hidden line cannot be used to walk to other hidden products' do
    line_on_hidden_product
    @soon_hidden.taxons << @taxon

    get '/api/v2/storefront/cart?include=variants.product.taxons.products', headers: headers
    assert_response :success
    assert_nothing_secret
  end

  test 'changing the quantity of a hidden line is refused with a 422 and leaves the line alone' do
    line = line_on_hidden_product(2)

    patch '/api/v2/storefront/cart/set_quantity', params: { line_item_id: line.id, quantity: 1 }, headers: headers
    assert_response :unprocessable_entity
    assert_match(/not available/i, media_json['error'])
    assert_equal 2, line.reload.quantity

    get '/api/v2/storefront/cart', headers: headers
    assert_response :success
  end

  test 'adding more of a hidden line already in the cart is refused with a 422 and leaves the line alone' do
    line = line_on_hidden_product(2)
    add_item(@soon_hidden.master, 1)
    assert_response :unprocessable_entity
    assert_equal 2, line.reload.quantity
  end

  test 'a hidden line can be removed' do
    line = line_on_hidden_product
    delete "/api/v2/storefront/cart/remove_line_item/#{line.id}", headers: headers
    assert_response :success
    assert_equal 0, order.line_items.count
    assert_equal 0, order.item_total
  end

  test 'a cart holding a hidden line can be emptied' do
    line_on_hidden_product
    patch '/api/v2/storefront/cart/empty', headers: headers
    assert_response :success
    assert_equal 0, order.line_items.count
  end

  test 'other products can still be added to a cart holding a hidden line, and changed' do
    line_on_hidden_product
    add_item(@visible.master, 1)
    assert_response :success
    other_line = order.line_items.find_by!(variant_id: @visible.master.id)
    patch '/api/v2/storefront/cart/set_quantity', params: { line_item_id: other_line.id, quantity: 3 }, headers: headers
    assert_response :success
    assert_equal 3, other_line.reload.quantity
    assert_equal 2, order.line_items.count
  end

  test 'control: a cart of visible products reaches completion through this rig' do
    add_item(@visible.master, 1)
    assert_response :success
    fill_in_addresses
    advance
    assert_response :success, response.body
    assert_equal 'payment', order.state
    pay
    complete
    assert_response :success, response.body
    assert order.completed?
  end

  test 'a cart holding a hidden line cannot complete checkout' do
    line = line_on_hidden_product
    add_item(@visible.master, 1)
    assert_response :success
    on_hand = @soon_hidden.master.stock_items.first.count_on_hand
    fill_in_addresses

    # Up to payment nothing objects.
    3.times do |step|
      patch '/api/v2/storefront/checkout/next', headers: headers
      assert_response :success, response.body
      assert_equal %w[address delivery payment][step], order.state
    end
    pay

    # The step to complete is refused before any payment is processed, and the order goes back
    # to address (Order#ensure_line_items_are_in_stock, then restart_checkout_flow).
    complete
    assert_response :unprocessable_entity, response.body
    assert_equal 'Some line items in this order have insufficient quantity.', media_json['error']

    current = order
    assert_equal 'address', current.state
    refute current.completed?
    assert_nil current.completed_at
    assert_equal %w[checkout], current.payments.map(&:state)
    assert_equal 2, current.line_items.count
    assert_equal on_hand, @soon_hidden.master.stock_items.first.reload.count_on_hand

    # advance also tries to reach complete, ends at address too, and doesn't report the refusal.
    advance
    assert_response :success, response.body
    assert_equal 'address', order.state
    refute order.completed?

    # The owner still has a working cart: they can see it and clear the line.
    get '/api/v2/storefront/cart?include=line_items,variants', headers: headers
    assert_response :success
    delete "/api/v2/storefront/cart/remove_line_item/#{line.id}", headers: headers
    assert_response :success
  end

  test 'removing the hidden line lets the rest of the cart complete' do
    line = line_on_hidden_product
    add_item(@visible.master, 1)
    delete "/api/v2/storefront/cart/remove_line_item/#{line.id}", headers: headers
    assert_response :success
    fill_in_addresses
    advance
    assert_response :success, response.body
    pay
    complete
    assert_response :success, response.body
    assert order.completed?
  end

  test 'publishing the product again frees the line' do
    line = line_on_hidden_product
    @soon_hidden.update!(available_on: 1.minute.ago)
    patch '/api/v2/storefront/cart/set_quantity', params: { line_item_id: line.id, quantity: 1 }, headers: headers
    assert_response :success
    assert_equal 1, line.reload.quantity
  end

  # --- new lines --------------------------------------------------------------------------

  def assert_refused_new_line
    assert_response :unprocessable_entity, "#{request.fullpath} answered #{response.status}: #{response.body[0, 300]}"
    assert_nothing_secret
    assert_equal 'This item is not available.', media_json['error']
    assert_equal 0, order.line_items.count
  end

  test 'a new line for a hidden product is refused with a 422 that does not name it' do
    hidden_products.each_value do |product|
      add_item(product.master, 1)
      assert_refused_new_line
    end
  end

  test 'a zero or negative quantity does not get a hidden product into a cart' do
    hidden_products.each_value do |product|
      add_item(product.master, 0, '?include=variants.images,variants.product')
      assert_refused_new_line
      add_item(product.master, -1, '?include=variants.images,variants.product')
      assert_refused_new_line
    end
  end

  test 'a line cannot be pointed at a hidden variant' do
    add_item(@visible.master, 1)
    line = order.line_items.first
    user = api_user
    order.update!(user: user)

    [1, 0].each do |quantity|
      put "/api/v1/orders/#{@number}.json", headers: api_key(user),
                                            params: { order: { line_items: { '0' => { id: line.id, variant_id: @null_on.master.id, quantity: quantity } } } }
      assert_response :unprocessable_entity, response.body
      assert_nothing_secret
      assert_equal @visible.master.id, line.reload.variant_id
      assert_equal 1, line.quantity
    end
  end

  test 'v1 refuses a new line for a hidden product' do
    user = api_user
    order.update!(user: user)
    [1, 0].each do |quantity|
      post "/api/v1/orders/#{@number}/line_items.json", headers: api_key(user),
                                                        params: { line_item: { variant_id: @null_on.master.id, quantity: quantity } }
      assert_response :unprocessable_entity, response.body
      assert_nothing_secret
      assert_equal 0, order.line_items.count
    end
  end

  test 'v1 order create and update cannot bring a hidden product in' do
    user = api_user
    post '/api/v1/orders.json', headers: api_key(user),
                                params: { order: { line_items: { '0' => { variant_id: @null_on.master.id, quantity: 0 } } } }
    assert_nothing_secret
    assert_equal 0, Spree::LineItem.where(variant_id: @null_on.master.id).count

    order.update!(user: user)
    put "/api/v1/orders/#{@number}.json", headers: api_key(user),
                                          params: { order: { line_items: { '0' => { variant_id: @null_on.master.id, quantity: 1 } } } }
    assert_nothing_secret
    assert_equal 0, Spree::LineItem.where(variant_id: @null_on.master.id).count
  end

  test 'v2 checkout update cannot bring a hidden product in' do
    add_item(@visible.master, 1)
    patch '/api/v2/storefront/checkout', headers: headers,
                                         params: { order: { line_items_attributes: { '0' => { variant_id: @null_on.master.id, quantity: 0 } } } }
    assert_nothing_secret
    assert_equal 0, Spree::LineItem.where(variant_id: @null_on.master.id).count
  end

  test 'adding a visible product still works, and a missing variant is still a 404' do
    add_item(@visible.master, 2)
    assert_response :success
    assert_equal 2, order.line_items.first.quantity

    post '/api/v2/storefront/cart/add_item', params: { variant_id: 0, quantity: 1 }, headers: headers
    assert_response :not_found
  end

  # Spree's OrderMerger saves the moved line, which fails on a hidden product, and then destroys
  # the guest order. Only spree_frontend's sign-in merges carts; the API never does.
  test 'merging a guest cart drops a hidden line without raising' do
    line = line_on_hidden_product
    target = Spree::Order.create!(store: Spree::Store.default, currency: 'USD')
    target.merge!(order)
    assert_nil Spree::LineItem.find_by(id: line.id)
    assert_empty target.reload.line_items
  end
end
