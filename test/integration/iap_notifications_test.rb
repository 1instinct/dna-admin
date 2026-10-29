require 'test_helper'

class IapNotificationsTest < ActionDispatch::IntegrationTest
  include IapTestHelpers

  APPLE_URL = '/api/v1/iap/apple/notifications'.freeze
  GOOGLE_URL = '/api/v1/iap/google/notifications'.freeze

  setup do
    setup_iap_config
    iap_product
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    @alice = create_user
  end

  def post_apple_notification(signed)
    post APPLE_URL, params: { signedPayload: signed }.to_json, headers: { 'Content-Type' => 'application/json' }
  end

  def post_app_purchase(user, jws = apple_jws)
    post '/api/v1/iap/transactions', params: { platform: 'apple', signed_payload: jws }.to_json,
                                     headers: bearer_for(user).merge('Content-Type' => 'application/json')
  end

  def rtdn(data, message_id: SecureRandom.hex(6), query: '')
    envelope = {
      message: { data: Base64.strict_encode64(data.to_json), messageId: message_id, publishTime: Time.current.utc.iso8601 },
      subscription: 'projects/example/subscriptions/play-rtdn'
    }
    post "#{GOOGLE_URL}#{query}", params: envelope.to_json, headers: { 'Content-Type' => 'application/json' }
  end

  def google_sub_notification(token, type = 2)
    { version: '1.0', packageName: PACKAGE, eventTimeMillis: ms(Time.current).to_s,
      subscriptionNotification: { version: '1.0', notificationType: type, purchaseToken: token, subscriptionId: GOOGLE_PRODUCT } }
  end

  # --- Apple -----------------------------------------------------------------

  test 'a notification that arrives before the app posts creates the transaction, linked later (review focus 2)' do
    post_apple_notification(apple_notification('SUBSCRIBED', subtype: 'INITIAL_BUY'))
    assert_response :ok

    txn = Spree::IapTransaction.take!
    assert_nil txn.user_id
    assert_equal 'active', txn.status
    assert_equal 1, txn.iap_notifications.count

    post_app_purchase(@alice)
    assert_response :ok
    assert_equal @alice.id, txn.reload.user_id
    assert pro?(@alice)
  end

  test 'renewals of an owned subscription are linked to the owner and extend the entitlement' do
    post_app_purchase(@alice)
    renewal = { transactionId: '2000000002', purchased_at: 1.hour.ago }
    post_apple_notification(apple_notification('DID_RENEW', transaction: renewal))

    assert_response :ok
    assert_equal 2, Spree::IapTransaction.where(user_id: @alice.id).count
    assert_equal Spree::IapTransaction.find_by(transaction_id: '2000000002'), entitlement_for(@alice).iap_transaction
  end

  test 'a refund notification revokes the entitlement and survives a later app re-post' do
    post_app_purchase(@alice)
    refund = { revocationDate: ms(10.minutes.ago), revocationReason: 0 }
    post_apple_notification(apple_notification('REFUND', transaction: refund))

    assert_response :ok
    txn = Spree::IapTransaction.take!
    assert_equal 'refunded', txn.status
    assert txn.revoked_at
    refute pro?(@alice)

    post_app_purchase(@alice, apple_jws(refund))
    assert_equal 'refunded', txn.reload.status
    refute pro?(@alice)
  end

  test 'refund reversed restores access' do
    post_app_purchase(@alice)
    post_apple_notification(apple_notification('REFUND', transaction: { revocationDate: ms(10.minutes.ago) }))
    post_apple_notification(apple_notification('REFUND_REVERSED'))

    assert_equal 'active', Spree::IapTransaction.take!.status
    assert pro?(@alice)
  end

  test 'REVOKE and EXPIRED end access' do
    post_app_purchase(@alice)
    post_apple_notification(apple_notification('REVOKE', transaction: { revocationDate: ms(1.minute.ago) }))
    assert_equal 'revoked', Spree::IapTransaction.take!.status
    refute pro?(@alice)

    bob = create_user
    post_app_purchase(bob, apple_jws(transactionId: '2000000050', originalTransactionId: '1000000050'))
    assert pro?(bob)
    post_apple_notification(apple_notification('EXPIRED', subtype: 'VOLUNTARY',
                                                           transaction: { transactionId: '2000000050', originalTransactionId: '1000000050', purchased_at: 31.days.ago }))
    assert_equal 'expired', Spree::IapTransaction.find_by(transaction_id: '2000000050').status
    refute pro?(bob)
  end

  test 'billing failure with grace period keeps access until the grace end; without it access stops' do
    post_app_purchase(@alice)
    lapsed = { purchased_at: 31.days.ago }
    renewal = { autoRenewStatus: 1, gracePeriodExpiresDate: ms(5.days.from_now), originalTransactionId: '1000000001' }
    post_apple_notification(apple_notification('DID_FAIL_TO_RENEW', subtype: 'GRACE_PERIOD', transaction: lapsed, renewal: renewal))

    txn = Spree::IapTransaction.take!
    assert_equal 'grace', txn.status
    assert pro?(@alice)

    post_apple_notification(apple_notification('DID_FAIL_TO_RENEW', transaction: lapsed, renewal: renewal.except(:gracePeriodExpiresDate)))
    assert_equal 'billing_retry', txn.reload.status
    refute pro?(@alice)
  end

  test 'auto-renew changes are recorded from the renewal info' do
    post_app_purchase(@alice)
    post_apple_notification(apple_notification('DID_CHANGE_RENEWAL_STATUS', subtype: 'AUTO_RENEW_DISABLED',
                                                                             renewal: { autoRenewStatus: 0 }))
    assert_equal false, Spree::IapTransaction.take!.auto_renew
    assert pro?(@alice)
  end

  test 'duplicate notifications are processed once' do
    signed = apple_notification('SUBSCRIBED', uuid: 'fixed-uuid-1')
    post_apple_notification(signed)
    post_apple_notification(signed)

    assert_response :ok
    assert_equal 1, Spree::IapNotification.where(notification_id: 'fixed-uuid-1').count
  end

  test 'TEST notifications are acknowledged' do
    post APPLE_URL, params: { signedPayload: iap_chain.sign({ notificationType: 'TEST', notificationUUID: 'test-1',
                                                             data: { bundleId: BUNDLE_ID, environment: 'Sandbox' } }) }.to_json,
                    headers: { 'Content-Type' => 'application/json' }
    assert_response :ok
    assert_equal 0, Spree::IapTransaction.count
  end

  test 'forged or foreign notifications are rejected' do
    rogue = IapTestPki::Chain.new(root_name: 'Rogue')
    post_apple_notification(apple_notification('SUBSCRIBED', chain: rogue))
    assert_response :bad_request
    assert_equal 'invalid_signature', JSON.parse(response.body)['error']

    post_apple_notification(apple_notification('SUBSCRIBED', bundle_id: 'com.other.app'))
    assert_response :bad_request

    post APPLE_URL, params: {}.to_json, headers: { 'Content-Type' => 'application/json' }
    assert_response :bad_request
    assert_equal 0, Spree::IapTransaction.count
  end

  # --- Google ----------------------------------------------------------------

  test 'an RTDN before the app posts creates the transaction from the Play API; the app post links it' do
    stub_google_token
    stub_google_subscription('g-1', google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))

    rtdn(google_sub_notification('g-1', 4))
    assert_response :ok
    txn = Spree::IapTransaction.take!
    assert_nil txn.user_id
    assert_equal 1, txn.iap_notifications.count

    post '/api/v1/iap/transactions', params: { platform: 'google', purchase_token: 'g-1', product_id: GOOGLE_PRODUCT }.to_json,
                                     headers: bearer_for(@alice).merge('Content-Type' => 'application/json')
    assert_response :ok
    assert_equal @alice.id, txn.reload.user_id
    assert pro?(@alice)
  end

  test 'an RTDN re-reads the subscription state (cancel, expiry)' do
    stub_google_token
    ack = { acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED' }
    stub_google_subscription('g-2', google_subscription_json(ack))
    post '/api/v1/iap/transactions', params: { platform: 'google', purchase_token: 'g-2', product_id: GOOGLE_PRODUCT }.to_json,
                                     headers: bearer_for(@alice).merge('Content-Type' => 'application/json')
    assert pro?(@alice)

    stub_google_subscription('g-2', google_subscription_json(ack.merge(subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED',
                                                                       lineItems: [{ productId: GOOGLE_PRODUCT, expiryTime: 1.minute.ago.utc.iso8601 }])))
    rtdn(google_sub_notification('g-2', 13))

    assert_response :ok
    assert_equal 'expired', Spree::IapTransaction.take!.status
    refute pro?(@alice)
  end

  test 'a voided purchase notification marks the transaction refunded' do
    stub_google_token
    stub_google_subscription('g-3', google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))
    post '/api/v1/iap/transactions', params: { platform: 'google', purchase_token: 'g-3', product_id: GOOGLE_PRODUCT }.to_json,
                                     headers: bearer_for(@alice).merge('Content-Type' => 'application/json')

    rtdn({ version: '1.0', packageName: PACKAGE, eventTimeMillis: ms(Time.current).to_s,
           voidedPurchaseNotification: { purchaseToken: 'g-3', orderId: 'GPA.0000-0000-0000-00001', productType: 1, refundType: 1 } })

    assert_response :ok
    assert_equal 'refunded', Spree::IapTransaction.take!.status
    refute pro?(@alice)
  end

  test 'notifications for another package are ignored, duplicates processed once' do
    rtdn({ packageName: 'com.other.app', testNotification: { version: '1.0' } }, message_id: 'm-1')
    assert_response :ok
    assert_equal 'ignored', JSON.parse(response.body)['status']

    rtdn({ packageName: PACKAGE, testNotification: { version: '1.0' } }, message_id: 'm-2')
    rtdn({ packageName: PACKAGE, testNotification: { version: '1.0' } }, message_id: 'm-2')
    assert_response :ok
    assert_equal 1, Spree::IapNotification.where(platform: 'google', notification_id: 'm-2').count
  end

  test 'a Play outage returns 503 so Pub/Sub retries, and the retry succeeds' do
    stub_google_token
    stub_google_subscription('g-4', {}, status: 503)
    rtdn(google_sub_notification('g-4'), message_id: 'm-retry')
    assert_response :service_unavailable

    stub_google_subscription('g-4', google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))
    rtdn(google_sub_notification('g-4'), message_id: 'm-retry')
    assert_response :ok
    assert_equal 1, Spree::IapTransaction.count
    assert Spree::IapNotification.find_by(notification_id: 'm-retry').processed_at
  end

  test 'the push endpoint token is enforced when configured; malformed bodies are 400' do
    Iap.config.google_rtdn_token = 'push-secret'
    rtdn({ packageName: PACKAGE, testNotification: {} })
    assert_response :unauthorized
    rtdn({ packageName: PACKAGE, testNotification: {} }, query: '?token=push-secret')
    assert_response :ok

    post "#{GOOGLE_URL}?token=push-secret", params: { message: { data: '%%%' } }.to_json, headers: { 'Content-Type' => 'application/json' }
    assert_response :bad_request
  end
end
