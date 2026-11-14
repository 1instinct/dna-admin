require 'test_helper'

# POST /api/v1/affiliate/clicks and PATCH /api/v1/orders/current/affiliate.
class Spree::Api::V1::AffiliateAttributionTest < ActionDispatch::IntegrationTest
  setup do
    affiliate_store
    @affiliate = approved_affiliate(code: 'good-code', cookie_days: 45)
  end

  def post_click(params, headers = {})
    post '/api/v1/affiliate/clicks', params: params.to_json,
                                     headers: { 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '203.0.113.9',
                                                'HTTP_USER_AGENT' => 'TestAgent/1.0' }.merge(headers)
  end

  def attach(code, headers)
    patch '/api/v1/orders/current/affiliate', params: { code: code }.to_json,
                                              headers: { 'CONTENT_TYPE' => 'application/json' }.merge(headers)
  end

  test 'click for approved code records click and returns cookie_days' do
    assert_difference -> { AffiliateClick.count }, 1 do
      post_click(code: 'GOOD-CODE', landing_path: '/products/thing?ref=good-code&email=a@b.c',
                 referrer: 'https://www.youtube.com/watch?v=1')
    end
    assert_response :success
    assert_equal({ 'ok' => true, 'cookie_days' => 45 }, json)

    click = AffiliateClick.last
    assert_equal @affiliate, click.affiliate_account
    assert_equal '/products/thing', click.landing_path
    assert_equal 'www.youtube.com', click.referrer_host
    assert_match(/\A[0-9a-f]{64}\z/, click.visitor_hash)
    refute_includes AffiliateClick.column_names, 'ip'
    assert_equal AffiliateClick.visitor_hash(ip: '203.0.113.9', user_agent: 'TestAgent/1.0'), click.visitor_hash
  end

  test 'unknown/unapproved code returns 204 and records nothing' do
    create(:affiliate_account, code: 'pending-code')
    create(:affiliate_account, code: 'suspended-code', status: 'suspended')
    assert_no_difference -> { AffiliateClick.count } do
      post_click(code: 'nope-nope')
      assert_response :no_content
      post_click(code: 'pending-code')
      assert_response :no_content
      post_click(code: 'suspended-code')
      assert_response :no_content
      post_click(code: '')
      assert_response :no_content
    end
  end

  test 'click endpoint needs no auth' do
    post_click(code: 'good-code')
    assert_response :success

    post_click({ code: 'good-code' }, 'Authorization' => 'Bearer not-a-real-token')
    assert_response :success
  end

  test 'attach sets affiliate on cart order once; second different code ignored' do
    buyer = create(:user)
    order = cart_order(user: buyer, email: buyer.email)
    approved_affiliate(code: 'other-code')

    attach('Good-Code', auth(buyer))
    assert_response :success
    assert_equal({ 'attached' => true }, json)
    order.reload
    assert_equal @affiliate.id, order.affiliate_account_id
    assert order.affiliate_attributed_at.present?
    attributed_at = order.affiliate_attributed_at

    attach('other-code', auth(buyer))
    assert_response :success
    assert_equal({ 'attached' => false }, json)
    assert_equal @affiliate.id, order.reload.affiliate_account_id
    assert_equal attributed_at.to_i, order.affiliate_attributed_at.to_i

    attach('good-code', auth(buyer))
    assert_response :success
    assert_equal({ 'attached' => true }, json)
  end

  test 'a different code replaces an attribution older than the cookie window' do
    order = cart_order
    other = approved_affiliate(code: 'newer-code')
    attach('good-code', 'X-Spree-Order-Token' => order.token)
    order.update_columns(affiliate_attributed_at: 46.days.ago) # good-code's cookie is 45 days

    attach('newer-code', 'X-Spree-Order-Token' => order.token)
    assert_response :success
    assert_equal({ 'attached' => true }, json)
    order.reload
    assert_equal other.id, order.affiliate_account_id
    assert order.affiliate_attributed_at > 1.minute.ago
  end

  test 'within the cookie window a different code is still ignored' do
    order = cart_order
    approved_affiliate(code: 'newer-code')
    attach('good-code', 'X-Spree-Order-Token' => order.token)
    order.update_columns(affiliate_attributed_at: 44.days.ago)

    attach('newer-code', 'X-Spree-Order-Token' => order.token)
    assert_equal({ 'attached' => false }, json)
    assert_equal @affiliate.id, order.reload.affiliate_account_id
  end

  test 'the same code refreshes an expired attribution' do
    order = cart_order
    attach('good-code', 'X-Spree-Order-Token' => order.token)
    order.update_columns(affiliate_attributed_at: 50.days.ago)

    attach('good-code', 'X-Spree-Order-Token' => order.token)
    assert_equal({ 'attached' => true }, json)
    assert order.reload.affiliate_attributed_at > 1.minute.ago
  end

  test 'the same visitor and code within 30 minutes count once' do
    assert_difference -> { AffiliateClick.count }, 1 do
      post_click(code: 'good-code', landing_path: '/a')
      post_click(code: 'good-code', landing_path: '/b')
    end
    assert_response :success
    assert_equal 45, json['cookie_days']

    AffiliateClick.update_all(created_at: 31.minutes.ago)
    assert_difference -> { AffiliateClick.count }, 1 do
      post_click(code: 'good-code')
    end
    assert_difference -> { AffiliateClick.count }, 1 do
      post_click({ code: 'good-code' }, 'HTTP_USER_AGENT' => 'OtherAgent/2.0')
    end
  end

  test 'clicks are rate limited per visitor' do
    Affiliates.config.rate_limits[:click] = { limit: 2, window: 1.minute }
    approved_affiliate(code: 'second-code')
    post_click(code: 'good-code')
    assert_response :success
    post_click(code: 'second-code')
    assert_response :success
    assert_no_difference -> { AffiliateClick.count } do
      post_click(code: 'good-code')
    end
    assert_response :too_many_requests

    post_click({ code: 'good-code' }, 'REMOTE_ADDR' => '198.51.100.4')
    assert_response :success
  ensure
    Affiliates.reset_config!
  end

  test 'attach with the order token for a guest cart' do
    order = cart_order
    attach('good-code', 'X-Spree-Order-Token' => order.token)
    assert_response :success
    assert_equal @affiliate.id, order.reload.affiliate_account_id
  end

  test 'attach ignored for affiliate\'s own order (self-referral)' do
    order = cart_order(user: @affiliate.user, email: @affiliate.user.email)
    attach('good-code', auth(@affiliate.user))
    assert_response :success
    assert_equal({ 'attached' => false }, json)
    assert_nil order.reload.affiliate_account_id
  end

  test 'attach on completed order 422' do
    order = complete_order!(cart_order)
    attach('good-code', 'X-Spree-Order-Token' => order.token)
    assert_response :unprocessable_entity
    assert_nil order.reload.affiliate_account_id
  end

  test 'attach with an unknown or unapproved code is 204 and changes nothing' do
    order = cart_order
    create(:affiliate_account, code: 'pending-code')
    attach('pending-code', 'X-Spree-Order-Token' => order.token)
    assert_response :no_content
    attach('nope-nope', 'X-Spree-Order-Token' => order.token)
    assert_response :no_content
    assert_nil order.reload.affiliate_account_id
  end

  test 'attach without an order is 404, with a bad token too' do
    attach('good-code', auth(create(:user)))
    assert_response :not_found
    attach('good-code', 'X-Spree-Order-Token' => 'missing-token')
    assert_response :not_found
    attach('good-code', {})
    assert_response :not_found
  end

  test 'attach cannot touch another user\'s order by token' do
    owner = create(:user)
    order = cart_order(user: owner, email: owner.email)
    attach('good-code', auth(create(:user)).merge('X-Spree-Order-Token' => order.token))
    assert_response :not_found
    assert_nil order.reload.affiliate_account_id
  end

  test 'attach with an invalid bearer is 401' do
    order = cart_order
    attach('good-code', bearer('not-a-real-token').merge('X-Spree-Order-Token' => order.token))
    assert_response :unauthorized
  end
end
