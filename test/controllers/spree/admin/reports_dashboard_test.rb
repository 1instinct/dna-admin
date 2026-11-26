require 'test_helper'

# /admin/reports: the analytics dashboard. Its top-products query used to
# 500 as soon as a completed order existed (LineItem#sku without variant_id).
class Spree::Admin::ReportsDashboardTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    Rails.cache.clear # Spree caches the default store across tests
    @store = Spree::Store.default
    unless @store.persisted?
      @store = Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: "reports-#{SecureRandom.hex(3)}",
                                    mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
    end
    admin = create(:user)
    admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    login_as(admin, scope: :spree_user)
  end

  teardown { Warden.test_reset! }

  test 'renders with no data' do
    get '/admin/reports'

    assert_response :success
    assert_select 'canvas#ordersChart'
  end

  test 'counts a completed order, charts it on its day and lists its variant' do
    shipping_category = Spree::ShippingCategory.create!(name: "reports-#{SecureRandom.hex(4)}")
    product = Spree::Product.create!(name: 'Widget', price: 25, shipping_category: shipping_category)
    product.master.update!(sku: 'WIDGET-1')
    order = Spree::Order.create!(email: 'buyer@example.com', store: @store, currency: 'USD')
    # Stock and store availability are not what this test is about.
    order.line_items.new(variant: product.master, quantity: 2, price: 25, currency: 'USD').save!(validate: false)
    order.update_columns(state: 'complete', completed_at: Time.current, total: 50)

    get '/admin/reports', params: { date_range: '7' }

    assert_response :success
    assert_select 'h2', text: '1'
    assert_select 'td', text: 'WIDGET-1'
    assert_includes response.body, %("#{Time.current.to_date.strftime('%m/%d')}")
    assert_match(/\[0(,0){5},1\]/, response.body, 'the 7-day orders series ends with today\'s order')
  end

  test 'an unknown date range falls back to 30 days' do
    get '/admin/reports', params: { date_range: '100000' }

    assert_response :success
    assert_includes response.body, 'Last 30 days'
  end
end
