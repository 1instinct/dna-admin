require 'test_helper'

# Wholesale accounts' orders are marked channel "wholesale" when they complete; admins can mark
# any order on its Customer page; the storefront can't set it.
class Spree::OrderWholesaleChannelTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @product = media_product(name: 'Wrap Top')
  end

  teardown { Warden.test_reset! }

  test 'the migration creates the wholesale role once' do
    require Rails.root.join('db/migrate/20261126120100_ensure_spree_wholesale_role.rb').to_s
    Spree::Role.where(name: 'wholesale').delete_all
    2.times { ActiveRecord::Migration.suppress_messages { EnsureSpreeWholesaleRole.new.up } }
    assert_equal 1, Spree::Role.where(name: 'wholesale').count
  end

  test 'completion marks a wholesale account\'s order' do
    order = reviews_order(@product, user: reviews_wholesale_user)
    order.finalize!
    assert_equal 'wholesale', order.reload.channel
  end

  test 'completion leaves retail orders alone' do
    order = reviews_order(@product, user: create(:user))
    order.finalize!
    assert_equal 'spree', order.reload.channel
  end

  test 'completion keeps a channel an admin already chose' do
    order = reviews_order(@product, user: reviews_wholesale_user, channel: 'phone')
    order.finalize!
    assert_equal 'phone', order.reload.channel
  end

  test 'admins see and set the channel on the order Customer page' do
    order = reviews_order(@product, user: create(:user))
    login_as(media_admin, scope: :spree_user)

    get "/admin/orders/#{order.number}/customer/edit"
    assert_response :success
    assert_includes response.body, 'Sales channel'
    assert_includes response.body, 'id="order_channel"'

    address = { firstname: 'A', lastname: 'B', address1: '1 Main', city: 'Town', zipcode: '12345', phone: '555',
                country_id: order.ship_address.country_id }
    put "/admin/orders/#{order.number}/customer",
        params: { order: { email: order.email, channel: 'wholesale', bill_address_attributes: address,
                           ship_address_attributes: address }, guest_checkout: 'false', user_id: order.user_id }
    assert_equal 'wholesale', order.reload.channel

    put "/admin/orders/#{order.number}/customer",
        params: { order: { email: order.email, channel: 'something-else', bill_address_attributes: address,
                           ship_address_attributes: address }, guest_checkout: 'false', user_id: order.user_id }
    assert_equal 'wholesale', order.reload.channel, 'unknown values are ignored'
  end

  test 'the storefront account says whether the user is wholesale' do
    get '/api/v2/storefront/account', headers: auth(reviews_wholesale_user)
    assert_response :success
    assert_equal true, JSON.parse(response.body)['data']['attributes']['is_wholesale']

    get '/api/v2/storefront/account', headers: auth(create(:user))
    assert_equal false, JSON.parse(response.body)['data']['attributes']['is_wholesale']
  end

  test 'the storefront checkout cannot set the channel' do
    post '/api/v2/storefront/cart'
    token = JSON.parse(response.body)['data']['attributes']['token']
    number = JSON.parse(response.body)['data']['attributes']['number']
    patch '/api/v2/storefront/checkout', headers: { 'X-Spree-Order-Token' => token },
                                         params: { order: { email: 'a@example.com', channel: 'wholesale' } }
    assert_equal 'spree', Spree::Order.find_by!(number: number).channel
  end
end
