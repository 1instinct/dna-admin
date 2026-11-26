require 'test_helper'
require 'minitest/mock'

# M4.1: a review request is scheduled when an order ships (Spree::ShipmentReviewRequestDecorator).
class ReviewRequests::ScheduleTest < ActiveSupport::TestCase
  setup do
    reviews_enable!
    @home = review_requests_home!
    @product = media_product(name: 'Wrap Top')
  end

  test 'domestic orders are emailed request_delay_days after shipping, international ones later' do
    shipped_at = Time.zone.parse('2026-11-01 10:00')
    domestic = review_requests_order(@product, completed_at: shipped_at)
    abroad = review_requests_order(@product, completed_at: shipped_at, country: reviews_country(iso: 'YY'))

    request = ReviewRequests::Schedule.call(domestic)
    assert_equal ['scheduled', shipped_at + 7.days, shipped_at + 67.days, domestic.email],
                 request.values_at(:status, :send_after, :expires_at, :email)
    assert_nil request.token_digest, 'the token is only made when the email goes out'

    assert_equal shipped_at + 10.days, ReviewRequests::Schedule.call(abroad).send_after
  end

  test 'falls back to the configured default country when the store has none' do
    @review_requests_store.update_columns(default_country_id: nil)
    order = review_requests_order(@product, country: reviews_country(iso: 'YY'))
    Spree::Config.stub(:[], ->(key) { key == :default_country_id ? @home.id : nil }) do
      assert ReviewRequests::Schedule.new(order).international?
    end
    order.ship_address.update_columns(country_id: @home.id)
    Spree::Config.stub(:[], ->(key) { key == :default_country_id ? @home.id : nil }) do
      refute ReviewRequests::Schedule.new(order.reload).international?
    end
  end

  test 'one request per order; a later shipment moves it while it is still scheduled' do
    first_shipped = Time.zone.parse('2026-11-01 10:00')
    order = review_requests_order(@product, completed_at: first_shipped)
    request = ReviewRequests::Schedule.call(order)
    order.shipments.create!(stock_location: reviews_stock_location, state: 'shipped', shipped_at: first_shipped + 3.days)

    assert_equal request, ReviewRequests::Schedule.call(order)
    assert_equal 1, Spree::ReviewRequest.where(order: order).count
    assert_equal first_shipped + 10.days, request.reload.send_after, 'the last shipment counts'

    request.update!(status: 'sent', sent_at: Time.current)
    order.shipments.create!(stock_location: reviews_stock_location, state: 'shipped', shipped_at: first_shipped + 9.days)
    ReviewRequests::Schedule.call(order)
    assert_equal first_shipped + 10.days, request.reload.send_after, 'a sent request is left alone'
  end

  test 'skipped when reviews are off, there is no email, nothing has shipped, or the address opted out' do
    reviews_enable!(enabled: false)
    assert_nil ReviewRequests::Schedule.call(review_requests_order(@product))

    reviews_enable!
    no_email = review_requests_order(@product)
    no_email.update_columns(email: nil)
    assert_nil ReviewRequests::Schedule.call(no_email)
    assert_nil ReviewRequests::Schedule.call(review_requests_order(@product, shipped: false))

    old = review_requests_order(@product, email: 'Out@Example.com')
    review_request_for(old, status: 'opted_out')
    assert_nil ReviewRequests::Schedule.call(review_requests_order(@product, email: 'out@example.com'))
    assert_equal 1, Spree::ReviewRequest.count
  end

  test 'wholesale orders get requests too' do
    order = review_requests_order(@product, user: reviews_wholesale_user)
    assert ReviewRequests::Schedule.call(order)
  end

  test 'shipping a shipment schedules the request' do
    order = review_requests_order(@product, shipped: false)
    shipment = order.shipments.first
    shipped_at = Time.zone.parse('2026-11-20 09:00')
    handler = Object.new
    handler.define_singleton_method(:perform) { shipment.update_columns(shipped_at: shipped_at) }

    Spree::ShipmentHandler.stub(:factory, handler) { shipment.ship! }

    assert_equal 'shipped', shipment.reload.state
    request = Spree::ReviewRequest.find_by(order: order)
    assert_equal shipped_at + 7.days, request.send_after
  end

  test 'a scheduling failure never stops a shipment' do
    order = review_requests_order(@product, shipped: false)
    shipment = order.shipments.first
    handler = Object.new
    handler.define_singleton_method(:perform) { nil }

    # A real SQL error: without the savepoint it would abort the shipment's transaction.
    broken = ->(_order) { Spree::ReviewRequest.connection.execute('SELECT * FROM no_such_table') }
    ReviewRequests::Schedule.stub(:call, broken) do
      Spree::ShipmentHandler.stub(:factory, handler) { assert shipment.ship! }
    end
    assert_equal 'shipped', shipment.reload.state
    assert_equal 0, Spree::ReviewRequest.count
  end
end
