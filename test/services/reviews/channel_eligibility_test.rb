require 'test_helper'

class Reviews::ChannelEligibilityTest < ActiveSupport::TestCase
  setup do
    @top = media_product(name: 'Wrap Top')
    @skirt = media_product(name: 'Slip Skirt')
    @user = create(:user)
  end

  test 'channel: retail by default' do
    assert_equal 'retail', Reviews::Channel.for(order: reviews_order(@top, user: @user))
  end

  test 'channel: wholesale when the order channel says so, even for a guest' do
    assert_equal 'wholesale', Reviews::Channel.for(order: reviews_order(@top, channel: 'wholesale'))
  end

  test 'channel: wholesale when the buyer has the wholesale role' do
    buyer = reviews_wholesale_user
    assert_equal 'wholesale', Reviews::Channel.for(order: reviews_order(@top, user: buyer))
    assert_equal 'wholesale', Reviews::Channel.for(user: buyer)
  end

  test 'allowed_scope: wholesale reviews only for wholesale accounts and admins' do
    assert_equal 'retail', Reviews::Channel.allowed_scope('retail', nil)
    assert_equal 'retail', Reviews::Channel.allowed_scope('bogus', nil)
    %w[all wholesale].each do |scope|
      assert_raises(Reviews::Error) { Reviews::Channel.allowed_scope(scope, nil) }
      assert_raises(Reviews::Error) { Reviews::Channel.allowed_scope(scope, @user) }
      assert_equal scope, Reviews::Channel.allowed_scope(scope, reviews_wholesale_user)
      assert_equal scope, Reviews::Channel.allowed_scope(scope, media_admin)
    end
  end

  test 'eligibility: shipped items on completed orders only' do
    reviews_order(@top, user: @user)
    reviews_order(@skirt, user: @user, shipped: false)
    assert_equal [@top.id], Reviews::Eligibility.for_user(@user).map { |item| item.product.id }
  end

  test 'eligibility: canceled and incomplete orders do not count' do
    reviews_order(@top, user: @user, state: 'canceled')
    reviews_order(@skirt, user: @user, state: 'cart')
    assert_empty Reviews::Eligibility.for_user(@user)
  end

  test 'eligibility: a product bought twice is listed once, from the latest order' do
    reviews_order(@top, user: @user, completed_at: 2.months.ago)
    latest = reviews_order(@top, user: @user, completed_at: 1.day.ago)
    items = Reviews::Eligibility.for_user(@user)
    assert_equal 1, items.size
    assert_equal latest.id, items.first.order.id
  end

  test 'eligibility: an existing review is attached to its item' do
    reviews_enable!
    reviews_order(@top, @skirt, user: @user)
    reviews_submit(@top, user: @user, rating: 4)
    items = Reviews::Eligibility.for_user(@user).index_by { |item| item.product.id }
    assert_equal 4, items[@top.id].existing_review.rating
    assert_nil items[@skirt.id].existing_review
  end

  test 'eligibility: a guest order from its email link' do
    order = reviews_order(@top, @skirt)
    assert_equal [@top.id, @skirt.id].sort, Reviews::Eligibility.for_order(order).map { |i| i.product.id }.sort
  end

  test 'eligibility: admin accounts review nothing' do
    admin = media_admin
    reviews_order(@top, user: admin)
    assert_empty Reviews::Eligibility.for_user(admin)
  end

  test 'eligibility: another customer\'s purchase does not count' do
    reviews_order(@top, user: create(:user))
    assert_nil Reviews::Eligibility.item(product: @top, user: @user)
  end
end
