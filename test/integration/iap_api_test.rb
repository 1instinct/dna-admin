require 'test_helper'

class IapApiTest < ActionDispatch::IntegrationTest
  include IapTestHelpers

  setup do
    setup_iap_config
    iap_product
    @alice = create_user
    @bob = create_user
  end

  def json
    JSON.parse(response.body)
  end

  def post_apple(user, jws = apple_jws, headers: nil)
    post '/api/v1/iap/transactions', params: { platform: 'apple', signed_payload: jws }.to_json,
                                     headers: (headers || bearer_for(user)).merge('Content-Type' => 'application/json')
  end

  test 'every user endpoint requires authentication' do
    post '/api/v1/iap/transactions', params: { platform: 'apple', signed_payload: apple_jws }
    assert_response :unauthorized
    assert_equal 'unauthorized', json['error']

    get '/api/v1/iap/entitlements'
    assert_response :unauthorized
    get '/api/v1/iap/transactions'
    assert_response :unauthorized
    post '/api/v1/iap/restore'
    assert_response :unauthorized
  end

  test 'expired or revoked OAuth tokens are refused' do
    token = Doorkeeper::AccessToken.create!(resource_owner_id: @alice.id, expires_in: 60)
    plain = token.respond_to?(:plaintext_token) && token.plaintext_token || token.token
    travel 2.minutes do
      get '/api/v1/iap/entitlements', headers: { 'Authorization' => "Bearer #{plain}" }
      assert_response :unauthorized
    end
    token.revoke
    get '/api/v1/iap/entitlements', headers: { 'Authorization' => "Bearer #{plain}" }
    assert_response :unauthorized
  end

  test 'POST transactions verifies, records and returns entitlements' do
    post_apple(@alice)

    assert_response :ok
    assert_equal '2000000001', json['transaction']['transaction_id']
    assert_equal 'active', json['transaction']['status']
    assert_equal 'pro', json['transaction']['entitlement']
    refute json['transaction'].key?('signed_payload')
    assert_equal [{ 'key' => 'pro', 'active' => true }], json['entitlements'].map { |e| e.slice('key', 'active') }
  end

  test 'the Spree API key header also authenticates' do
    @alice.generate_spree_api_key!
    post_apple(@alice, headers: { 'X-Spree-Token' => @alice.spree_api_key })
    assert_response :ok
  end

  test 'errors are explicit codes with matching HTTP statuses' do
    post_apple(@alice, apple_jws(bundleId: 'com.other.app'))
    assert_response :unprocessable_entity
    assert_equal 'wrong_bundle', json['error']

    post_apple(@alice, 'garbage')
    assert_response :unprocessable_entity
    assert_equal 'invalid_signature', json['error']

    post_apple(@alice)
    post_apple(@bob)
    assert_response :conflict
    assert_equal 'already_owned_by_other_user', json['error']

    configure_apple_api!
    stub_request(:get, /api\.storekit/).to_timeout
    post_apple(@alice, apple_jws(transactionId: '2000000099'))
    assert_response :service_unavailable
    assert_equal 'store_unreachable', json['error']
  end

  test 'entitlements and transactions are scoped to the caller' do
    post_apple(@alice)
    alice_txn = Spree::IapTransaction.take!

    get '/api/v1/iap/entitlements', headers: bearer_for(@bob)
    assert_response :ok
    assert_equal [], json['entitlements']

    get '/api/v1/iap/transactions', headers: bearer_for(@bob)
    assert_equal [], json['transactions']

    get "/api/v1/iap/transactions/#{alice_txn.id}", headers: bearer_for(@bob)
    assert_response :not_found

    get "/api/v1/iap/transactions/#{alice_txn.id}", headers: bearer_for(@alice)
    assert_response :ok
    assert_equal alice_txn.transaction_id, json['transaction']['transaction_id']

    get '/api/v1/iap/entitlements', headers: bearer_for(@alice)
    assert_equal 'pro', json['entitlements'].first['key']
    assert json['entitlements'].first['active']
  end

  test 'restore records each purchase and reports per-item results' do
    purchases = [
      { platform: 'apple', signed_payload: apple_jws },
      { platform: 'apple', signed_payload: apple_jws(transactionId: '2000000002', originalTransactionId: '1000000002', purchased_at: 60.days.ago) },
      { platform: 'apple', signed_payload: apple_jws(bundleId: 'com.other.app') }
    ]
    post '/api/v1/iap/restore', params: { purchases: purchases }.to_json,
                                headers: bearer_for(@alice).merge('Content-Type' => 'application/json')

    assert_response :ok
    assert_equal %w[ok ok error], json['results'].map { |r| r['status'] }
    assert_equal 'wrong_bundle', json['results'].last['error']
    assert_equal 2, Spree::IapTransaction.where(user_id: @alice.id).count
    assert json['entitlements'].first['active']
  end

  test 'restore caps the batch size' do
    purchases = Array.new(101) { { platform: 'apple', signed_payload: 'x' } }
    post '/api/v1/iap/restore', params: { purchases: purchases }.to_json,
                                headers: bearer_for(@alice).merge('Content-Type' => 'application/json')
    assert_response :unprocessable_entity
    assert_equal 'too_many_purchases', json['error']
  end

  test 'products lists the active catalogue without authentication' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    Spree::IapProduct.create!(platform: 'apple', product_id: 'example.retired', kind: 'subscription', active: false)

    get '/api/v1/iap/products'

    assert_response :ok
    ids = json['products'].map { |p| p['product_id'] }
    assert_includes ids, APPLE_PRODUCT
    assert_includes ids, GOOGLE_PRODUCT
    refute_includes ids, 'example.retired'

    get '/api/v1/iap/products', params: { platform: 'google' }
    assert_equal [GOOGLE_PRODUCT], json['products'].map { |p| p['product_id'] }
  end
end
