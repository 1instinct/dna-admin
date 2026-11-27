# Shared setup for the review tests: settings switched on, completed orders whose shipments
# have (or haven't) shipped, and wholesale accounts. Orders are written straight to their final
# state, without going through checkout, so a test reads as the purchase it needs.
module ReviewsTestHelper
  def reviews_enable!(**overrides)
    settings = Spree::ReviewSetting.current
    settings.update!({ enabled: true }.merge(overrides))
    settings
  end

  def reviews_country(iso: 'ZZ')
    Spree::Country.find_by(iso: iso) ||
      Spree::Country.create!(iso: iso, iso3: "#{iso}#{iso[0]}", iso_name: "TEST #{iso}", name: "Test #{iso}",
                             states_required: false, zipcode_required: false)
  end

  def reviews_address(country: reviews_country, firstname: 'Maya', lastname: 'Rivera')
    Spree::Address.create!(firstname: firstname, lastname: lastname, address1: '1 Main St', city: 'Town',
                           zipcode: '12345', phone: '5550100', country: country)
  end

  def reviews_stock_location
    @reviews_stock_location ||= Spree::StockLocation.create!(name: "Reviews #{SecureRandom.hex(2)}", active: true,
                                                             propagate_all_variants: false, country: reviews_country)
  end

  # A completed order for these variants (or products' masters). shipped: false leaves the
  # shipment ready; state: 'canceled' cancels it.
  def reviews_order(*items, user: nil, shipped: true, state: 'complete', channel: 'spree', completed_at: Time.current,
                    country: reviews_country, email: nil)
    address = reviews_address(country: country)
    order = Spree::Order.create!(user: user, email: email || user&.email || "guest-#{SecureRandom.hex(3)}@example.com",
                                 store: media_store, currency: 'USD', channel: channel,
                                 bill_address: address, ship_address: address)
    shipment = order.shipments.create!(stock_location: reviews_stock_location, state: shipped ? 'shipped' : 'ready',
                                       shipped_at: shipped ? completed_at : nil)
    items.each do |item|
      variant = item.is_a?(Spree::Product) ? item.master : item
      reviews_stock_location.stock_item_or_create(variant).set_count_on_hand(10)
      line_item = Spree::LineItem.new(order: order, variant: variant, quantity: 1, price: 10, currency: 'USD')
      line_item.save!(validate: false)
      Spree::InventoryUnit.create!(order: order, shipment: shipment, variant: variant, line_item: line_item,
                                   state: shipped ? 'shipped' : 'on_hand', quantity: 1)
    end
    order.update_columns(state: state, completed_at: state == 'complete' ? completed_at : nil)
    order.reload
  end

  def reviews_wholesale_user
    user = create(:user)
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'wholesale')
    user
  end

  # The store that store reviews belong to (Reviews.store): a real default row. media_store can
  # return a cached Spree::Store.default that another test rolled back.
  def reviews_store
    Reviews.store || Spree::Store.create!(name: 'Test Store', url: 'store-reviews.example.com', code: "sr-#{SecureRandom.hex(3)}",
                                          mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
  end

  def reviews_submit(reviewable, user: nil, review_request: nil, **params)
    Reviews::Submit.call(reviewable: reviewable, user: user, review_request: review_request, params: params)
  end

  def reviews_photo(name = 'photo.png')
    { io: StringIO.new(ShopMediaTestHelper::PNG_BYTES), filename: name, content_type: 'image/png' }
  end
end

ActiveSupport::TestCase.include(ReviewsTestHelper)
