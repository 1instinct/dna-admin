require 'test_helper'

class Iap::RecorderTest < ActiveSupport::TestCase
  include IapTestHelpers

  setup do
    setup_iap_config
    iap_product
    @alice = create_user
    @bob = create_user
  end

  def record(user, platform = 'apple', payload = { signed_payload: apple_jws })
    Iap::Recorder.new.record(user, platform, payload)
  end

  # --- Apple -----------------------------------------------------------------

  test 'records a verified Apple transaction and grants the product entitlement' do
    txn = record(@alice)

    assert txn.persisted?
    assert_equal @alice.id, txn.user_id
    assert_equal 'apple', txn.platform
    assert_equal 'active', txn.status
    assert_equal 'production', txn.environment
    assert_equal BigDecimal('9.99'), txn.price
    assert txn.verified_at
    assert_equal Spree::IapProduct.find_by(product_id: APPLE_PRODUCT), txn.iap_product
    assert pro?(@alice)
    assert_equal txn, entitlement_for(@alice).iap_transaction
  end

  test 're-posting the same transaction is idempotent' do
    first = record(@alice)
    second = record(@alice)

    assert_equal first.id, second.id
    assert_equal 1, Spree::IapTransaction.count
    assert_equal 1, Spree::Entitlement.where(user_id: @alice.id).count
  end

  test 'a transaction owned by another user is refused and grants nothing (review focus 1)' do
    record(@alice)

    assert_iap_error(:already_owned_by_other_user) { record(@bob) }
    refute pro?(@bob)
    assert_nil entitlement_for(@bob)
    assert_equal @alice.id, Spree::IapTransaction.take!.user_id
  end

  test 'a renewal of a subscription owned by another user is refused too' do
    record(@alice)
    renewal = apple_jws(transactionId: '2000000002', purchased_at: Time.current)

    assert_iap_error(:already_owned_by_other_user) { record(@bob, 'apple', signed_payload: renewal) }
    refute pro?(@bob)
    assert_equal 1, Spree::IapTransaction.count
  end

  test 'an expired subscription is recorded but the entitlement is inactive' do
    txn = record(@alice, 'apple', signed_payload: apple_jws(purchased_at: 40.days.ago))

    assert_equal 'expired', txn.status
    refute pro?(@alice)
    refute entitlement_for(@alice).active
  end

  test 'sandbox purchases are recorded as sandbox' do
    txn = record(@alice, 'apple', signed_payload: apple_jws(environment: 'Sandbox'))
    assert_equal 'sandbox', txn.environment
  end

  test 'invalid signatures and wrong bundles record nothing' do
    rogue = IapTestPki::Chain.new(root_name: 'Rogue')
    assert_iap_error(:invalid_signature) { record(@alice, 'apple', signed_payload: apple_jws({}, chain: rogue)) }
    assert_iap_error(:wrong_bundle) { record(@alice, 'apple', signed_payload: apple_jws(bundleId: 'com.other.app')) }
    assert_iap_error(:invalid_payload) { record(@alice, 'apple', {}) }
    assert_iap_error(:invalid_platform) { record(@alice, 'web', signed_payload: apple_jws) }
    assert_equal 0, Spree::IapTransaction.count
  end

  test 'consumables never grant an entitlement' do
    iap_product(product_id: 'example.coins', kind: 'consumable', entitlement: nil)
    record(@alice, 'apple', signed_payload: apple_jws(productId: 'example.coins', type: 'Consumable', expiresDate: nil))
    assert_equal 0, Spree::Entitlement.count
  end

  test 'a product added to the catalogue later picks up existing transactions' do
    record(@alice, 'apple', signed_payload: apple_jws(productId: 'example.pro.yearly'))
    refute pro?(@alice)

    iap_product(product_id: 'example.pro.yearly')

    assert pro?(@alice)
  end

  test 'with App Store Server API credentials the authoritative state wins' do
    configure_apple_api!
    revoked = apple_jws(revocationDate: ms(1.hour.ago), revocationReason: 1)
    stub_request(:get, %r{api\.storekit\.itunes\.apple\.com/inApps/v1/transactions/2000000001})
      .to_return(status: 200, body: { signedTransactionInfo: revoked }.to_json)

    txn = record(@alice)

    assert_equal 'revoked', txn.status
    refute pro?(@alice)
  end

  test 'an unreachable App Store records nothing and raises store_unreachable' do
    configure_apple_api!
    stub_request(:get, %r{api\.storekit\.itunes\.apple\.com}).to_return(status: 503)

    assert_iap_error(:store_unreachable) { record(@alice) }
    assert_equal 0, Spree::IapTransaction.count
  end

  test 'an admin revocation sticks when the app posts the transaction again' do
    txn = record(@alice)
    Iap::AdminRevocation.new(txn, admin: create_user, note: 'chargeback').call

    assert_equal 'revoked', record(@alice).status
    refute pro?(@alice)
  end

  # --- Google ----------------------------------------------------------------

  def google_payload(token = 'gtoken-1', sku = GOOGLE_PRODUCT)
    { purchase_token: token, product_id: sku }
  end

  test 'records a Google subscription verified through the Play Developer API and acknowledges it' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    stub_google_token
    stub_google_subscription('gtoken-1', google_subscription_json)
    ack = stub_google_acknowledge('subscriptions', GOOGLE_PRODUCT, 'gtoken-1')

    txn = record(@alice, 'google', google_payload)

    assert_equal 'google', txn.platform
    assert_equal 'gtoken-1', txn.transaction_id
    assert_equal 'active', txn.status
    assert txn.auto_renew
    assert_equal 'GPA.0000-0000-0000-00001', txn.order_id
    assert txn.acknowledged_at
    assert_requested ack
    assert pro?(@alice)
  end

  test 'already-acknowledged Google purchases are not acknowledged again' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    stub_google_token
    stub_google_subscription('gtoken-1', google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))

    record(@alice, 'google', google_payload)
    assert_not_requested(:post, /:acknowledge/)
  end

  test 'Google test purchases are sandbox, expired and pending states grant nothing' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    stub_google_token
    stub_google_subscription('t-test', google_subscription_json(testPurchase: {},
                                                                acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))
    stub_google_subscription('t-exp', google_subscription_json(subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED',
                                                               acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
                                                               lineItems: [{ productId: GOOGLE_PRODUCT, expiryTime: 1.day.ago.utc.iso8601 }]))
    stub_google_subscription('t-pend', google_subscription_json(subscriptionState: 'SUBSCRIPTION_STATE_PENDING'))

    assert_equal 'sandbox', record(@alice, 'google', google_payload('t-test')).environment
    assert_equal 'expired', record(@bob, 'google', google_payload('t-exp')).status
    carol = create_user
    assert_equal 'pending', record(carol, 'google', google_payload('t-pend')).status
    refute pro?(@bob)
    refute pro?(carol)
    assert_not_requested(:post, %r{tokens/t-pend:acknowledge})
  end

  test 'Google grace period keeps access, on hold does not' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    stub_google_token
    stub_google_subscription('t-grace', google_subscription_json(subscriptionState: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
                                                                 acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))
    stub_google_subscription('t-hold', google_subscription_json(subscriptionState: 'SUBSCRIPTION_STATE_ON_HOLD',
                                                                acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))

    assert_equal 'grace', record(@alice, 'google', google_payload('t-grace')).status
    assert pro?(@alice)
    assert_equal 'billing_retry', record(@bob, 'google', google_payload('t-hold')).status
    refute pro?(@bob)
  end

  test 'a Google upgrade (linkedPurchaseToken) supersedes the old token and keeps ownership' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    stub_google_token
    ack_state = { acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED' }
    stub_google_subscription('old', google_subscription_json(ack_state))
    stub_google_subscription('new', google_subscription_json(ack_state.merge(linkedPurchaseToken: 'old')))

    old = record(@alice, 'google', google_payload('old'))
    assert_iap_error(:already_owned_by_other_user) { record(@bob, 'google', google_payload('new')) }

    fresh = record(@alice, 'google', google_payload('new'))
    assert_equal old.original_transaction_id, fresh.original_transaction_id
    assert_equal 'expired', old.reload.status
    assert pro?(@alice)
  end

  test 'Google one-time products are verified with the products API' do
    iap_product(platform: 'google', product_id: 'example_lifetime', kind: 'non_consumable')
    stub_google_token
    stub_google_product('example_lifetime', 'p-1', { purchaseTimeMillis: ms(1.hour.ago).to_s, purchaseState: 0,
                                                     acknowledgementState: 0, orderId: 'GPA.1', purchaseType: 0 })
    ack = stub_google_acknowledge('products', 'example_lifetime', 'p-1')

    txn = record(@alice, 'google', google_payload('p-1', 'example_lifetime'))

    assert_equal 'active', txn.status
    assert_nil txn.expires_at
    assert_equal 'sandbox', txn.environment
    assert_requested ack
    assert pro?(@alice)
  end

  test 'an unknown Google product needs a type hint' do
    stub_google_token
    assert_iap_error(:unknown_product) { record(@alice, 'google', google_payload('x', 'nope')) }
  end

  test 'a Google acknowledgement failure does not lose the verified purchase' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    stub_google_token
    stub_google_subscription('gtoken-1', google_subscription_json)
    stub_request(:post, /:acknowledge/).to_return(status: 503)

    txn = record(@alice, 'google', google_payload)
    assert txn.persisted?
    assert_nil txn.acknowledged_at
    assert pro?(@alice)
  end

  test 'Play outages surface as store_unreachable' do
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    stub_google_token
    stub_google_subscription('gtoken-1', {}, status: 500)
    assert_iap_error(:store_unreachable) { record(@alice, 'google', google_payload) }
  end
end
