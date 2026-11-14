# Shared helpers for the affiliates module tests: a store, products in stock and orders taken
# through Spree's real checkout state machine to `complete`.
module AffiliatesTestHelper
  def affiliate_store
    store = Spree::Store.default
    return store if store.persisted?

    Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: "test-#{SecureRandom.hex(3)}",
                         mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
  end

  def affiliate_product(price: 50)
    store = affiliate_store
    Spree::StockLocation.first || Spree::StockLocation.create!(name: 'Default', backorderable_default: true,
                                                                propagate_all_variants: true)
    shipping_category = Spree::ShippingCategory.first || Spree::ShippingCategory.create!(name: 'Default')
    product = Spree::Product.new(name: "Affiliate item #{SecureRandom.hex(3)}", price: price, available_on: 1.day.ago,
                                 shipping_category: shipping_category)
    product.stores << store if product.respond_to?(:stores)
    product.save!
    product.master.stock_items.each { |item| item.update!(backorderable: true) }
    product
  end

  # An order in the cart state holding one of each product.
  def cart_order(user: nil, email: 'buyer@example.com', products: nil)
    products ||= [affiliate_product]
    order = Spree::Order.create!(user: user, email: email, store: affiliate_store, currency: 'USD')
    products.each { |product| Spree::Cart::AddItem.call(order: order, variant: product.master, quantity: 1) }
    order.update_with_updater!
    order.reload
  end

  # Takes the order from wherever it is to `complete` through the state machine, paid by check.
  def complete_order!(order)
    order.update_with_updater!
    order.update_columns(state: 'confirm')
    order.payments.create!(amount: order.total, payment_method: check_payment_method, state: 'checkout')
    order.reload.complete!
    order.reload
  end

  def check_payment_method
    Spree::PaymentMethod::Check.first || begin
      method = Spree::PaymentMethod::Check.new(name: 'Check', active: true)
      method.stores << affiliate_store if method.respond_to?(:stores)
      method.save!
      method
    end
  end

  def approved_affiliate(code: "aff-#{SecureRandom.hex(3)}", **attrs)
    create(:affiliate_account, :approved, code: code, **attrs)
  end
end

ActiveSupport::TestCase.include(AffiliatesTestHelper)
