require 'test_helper'
require 'minitest/mock'

# Regression tests for the PR #114 security review.
class IapHardeningTest < ActionDispatch::IntegrationTest
  include IapTestHelpers
  include Devise::Test::IntegrationHelpers

  APPLE_URL = '/api/v1/iap/apple/notifications'.freeze
  GOOGLE_URL = '/api/v1/iap/google/notifications'.freeze

  setup do
    setup_iap_config
    iap_product
    iap_product(platform: 'google', product_id: GOOGLE_PRODUCT)
    @alice = create_user
    @bob = create_user
  end

  def json
    JSON.parse(response.body)
  end

  def post_apple_notification(signed)
    post APPLE_URL, params: { signedPayload: signed }.to_json, headers: { 'Content-Type' => 'application/json' }
  end

  def post_purchase(user, body)
    post '/api/v1/iap/transactions', params: body.to_json, headers: bearer_for(user).merge('Content-Type' => 'application/json')
  end

  def post_apple(user, jws = apple_jws)
    post_purchase(user, platform: 'apple', signed_payload: jws)
  end

  def rtdn(data, message_id: SecureRandom.hex(6), headers: { 'Authorization' => "Bearer #{push_token}" })
    stub_google_certs
    envelope = { message: { data: Base64.strict_encode64(data.to_json), messageId: message_id } }
    post GOOGLE_URL, params: envelope.to_json, headers: headers.merge('Content-Type' => 'application/json')
  end

  def rtdn_test_message
    { version: '1.0', packageName: PACKAGE, testNotification: { version: '1.0' } }
  end

  def account_token_for(user)
    get '/api/v1/iap/account_token', headers: bearer_for(user)
    json['account_token']
  end

  # --- 1: stale Apple notifications --------------------------------------------

  test 'an older SUBSCRIBED notification retried after a REFUND does not regrant' do
    stale = apple_notification('SUBSCRIBED', signed_at: 2.hours.ago)
    post_apple(@alice)
    post_apple_notification(apple_notification('REFUND', transaction: { revocationDate: ms(1.hour.ago) }))
    assert_equal 'refunded', Spree::IapTransaction.take!.status

    post_apple_notification(stale)
    assert_response :ok
    assert_equal 'refunded', Spree::IapTransaction.take!.status
    refute pro?(@alice)
  end

  test 'a newer non-reversal notification does not clear a refund; REFUND_REVERSED does' do
    post_apple(@alice)
    post_apple_notification(apple_notification('REFUND', transaction: { revocationDate: ms(1.hour.ago) }))
    post_apple_notification(apple_notification('ONE_TIME_CHARGE', signed_at: 1.second.from_now))
    assert_equal 'refunded', Spree::IapTransaction.take!.status
    refute pro?(@alice)

    post_apple_notification(apple_notification('REFUND_REVERSED', signed_at: 1.minute.from_now))
    assert_equal 'active', Spree::IapTransaction.take!.status
    assert pro?(@alice)
  end

  test 'an older notification never overwrites newer state' do
    post_apple_notification(apple_notification('EXPIRED', transaction: { purchased_at: 31.days.ago }))
    post_apple_notification(apple_notification('DID_RENEW', signed_at: 1.day.ago))
    assert_equal 'expired', Spree::IapTransaction.take!.status
  end

  # --- 2/3: Google push authentication -----------------------------------------

  test 'RTDN pushes without a valid OIDC token are refused' do
    rtdn(rtdn_test_message, headers: {})
    assert_response :unauthorized

    {
      'wrong audience' => push_token(aud: 'https://evil.example.com/hook'),
      'wrong account' => push_token(email: 'someone@example.com'),
      'unverified email' => push_token(email_verified: false),
      'wrong issuer' => push_token(iss: 'https://evil.example.com'),
      'expired' => push_token(exp: 1.hour.ago.to_i, iat: 2.hours.ago.to_i),
      'foreign key' => push_token({}, key: OpenSSL::PKey::RSA.new(2048))
    }.each do |label, token|
      rtdn(rtdn_test_message, headers: { 'Authorization' => "Bearer #{token}" })
      assert_response :unauthorized, label
    end
    assert_equal 0, Spree::IapNotification.count

    rtdn(rtdn_test_message)
    assert_response :ok
  end

  test 'the endpoint is closed when no push authentication is configured' do
    Iap.config.google_rtdn_audience = nil
    Iap.config.google_rtdn_service_account = nil
    rtdn(rtdn_test_message)
    assert_response :unauthorized
  end

  test 'the shared push token works only as an opt-in header, never in the query string' do
    Iap.config.google_rtdn_token = 'push-secret'
    stub_google_certs
    envelope = { message: { data: Base64.strict_encode64(rtdn_test_message.to_json), messageId: 'q-1' } }.to_json
    post "#{GOOGLE_URL}?token=push-secret", params: envelope, headers: { 'Content-Type' => 'application/json' }
    assert_response :unauthorized

    rtdn(rtdn_test_message, headers: { 'X-Iap-Push-Token' => 'wrong' })
    assert_response :unauthorized
    rtdn(rtdn_test_message, headers: { 'X-Iap-Push-Token' => 'push-secret' })
    assert_response :ok
  end

  test 'RTDN status comes from the Play API, not the notification type' do
    stub_google_token
    stub_google_subscription('g-12', google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))
    rtdn({ packageName: PACKAGE, subscriptionNotification: { notificationType: 12, purchaseToken: 'g-12', subscriptionId: GOOGLE_PRODUCT } })

    assert_response :ok
    assert_equal 'active', Spree::IapTransaction.take!.status
  end

  def void_rtdn(token, message_id:, published_at:)
    stub_google_certs
    data = { packageName: PACKAGE, eventTimeMillis: ms(published_at).to_s,
             voidedPurchaseNotification: { purchaseToken: token, productType: 1, refundType: 1 } }
    envelope = { message: { data: Base64.strict_encode64(data.to_json), messageId: message_id,
                            publishTime: published_at.utc.iso8601 } }
    post GOOGLE_URL, params: envelope.to_json,
                     headers: { 'Authorization' => "Bearer #{push_token}", 'Content-Type' => 'application/json' }
  end

  def google_purchase_for_alice(token)
    stub_google_token
    stub_google_subscription(token, google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))
    post_purchase(@alice, platform: 'google', purchase_token: token, product_id: GOOGLE_PRODUCT)
  end

  test 'an unconfirmed void is retried (503, no dedupe row) and applied once the Play API shows it' do
    google_purchase_for_alice('g-v')
    stub_request(:get, /voidedpurchases/).to_return(status: 200, body: { voidedPurchases: [] }.to_json)

    void_rtdn('g-v', message_id: 'v-1', published_at: 5.minutes.ago)
    assert_response :service_unavailable
    assert_nil Spree::IapNotification.find_by(notification_id: 'v-1')
    assert_equal 'active', Spree::IapTransaction.take!.status
    assert pro?(@alice)

    stub_request(:get, /voidedpurchases/)
      .to_return(status: 200, body: { voidedPurchases: [{ purchaseToken: 'g-v', voidedTimeMillis: ms(4.minutes.ago).to_s }] }.to_json)
    void_rtdn('g-v', message_id: 'v-1', published_at: 5.minutes.ago)
    assert_response :ok
    assert_equal 'refunded', Spree::IapTransaction.take!.status
    refute pro?(@alice)
  end

  test 'a void still unconfirmed after 24 hours is parked for manual review in IAP Orders' do
    google_purchase_for_alice('g-v2')
    stub_request(:get, /voidedpurchases/).to_return(status: 200, body: { voidedPurchases: [] }.to_json)

    void_rtdn('g-v2', message_id: 'v-2', published_at: 25.hours.ago)

    assert_response :ok
    txn = Spree::IapTransaction.take!
    assert_equal 'active', txn.status
    note = Spree::IapNotification.find_by(notification_id: 'v-2')
    assert note.processed_at
    assert_equal 'void_unconfirmed', note.error
    assert_equal txn, note.iap_transaction

    admin = create_user
    admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    sign_in admin, scope: :spree_user
    get '/admin/iap_transactions'
    assert_select '#iap_needs_review', text: /1 purchase/
    assert_select "#iap_transaction_#{txn.id} .iap-needs-review"
    get '/admin/iap_transactions', params: { needs_review: 1 }
    assert_select "#iap_transaction_#{txn.id}"
  end

  test 'a message for another package leaves no dedupe row to suppress the real one' do
    rtdn(rtdn_test_message.merge(packageName: 'com.other.app'), message_id: 'shared-id')
    assert_response :ok
    assert_nil Spree::IapNotification.find_by(notification_id: 'shared-id')

    stub_google_token
    stub_google_subscription('g-real', google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'))
    rtdn({ packageName: PACKAGE, subscriptionNotification: { notificationType: 4, purchaseToken: 'g-real', subscriptionId: GOOGLE_PRODUCT } },
         message_id: 'shared-id')
    assert_response :ok
    assert Spree::IapNotification.find_by(notification_id: 'shared-id').processed_at
    assert_equal 1, Spree::IapTransaction.count
  end

  # --- 4: App Store Server API required in production --------------------------

  test 'without the App Store Server API key a required check records unverified and grants nothing' do
    Iap.config.require_apple_api = true
    post_apple(@alice, apple_jws(signedDate: ms(1.minute.ago)))

    assert_response :ok
    assert_equal 'unverified', json['transaction']['status']
    refute pro?(@alice)

    # Apple's own notification (signed before the device post) then confirms it.
    post_apple_notification(apple_notification('SUBSCRIBED', signed_at: 2.minutes.ago))
    assert_equal 'active', Spree::IapTransaction.take!.status
    assert_equal @alice.id, Spree::IapTransaction.take!.user_id
    assert pro?(@alice)
  end

  test 'production requires the App Store Server API by default' do
    assert Iap::Configuration.from_env('IAP_REQUIRE_APPLE_API' => 'true').require_apple_api
    refute Iap::Configuration.from_env({}).require_apple_api
    Rails.env.stub(:production?, true) do
      assert Iap::Configuration.from_env({}).require_apple_api
    end
    missing = Iap::Configuration.from_env('APPLE_BUNDLE_ID' => 'com.example.app').missing_settings
    assert_equal %w[APPLE_IAP_KEY_ID APPLE_IAP_ISSUER_ID APPLE_IAP_PRIVATE_KEY], missing
  end

  # --- 5: sandbox switch for Google ---------------------------------------------

  test 'IAP_ALLOW_SANDBOX=false rejects Google test purchases' do
    Iap.config.allow_sandbox = false
    stub_google_token
    stub_google_subscription('g-test', google_subscription_json(testPurchase: {}))

    post_purchase(@alice, platform: 'google', purchase_token: 'g-test', product_id: GOOGLE_PRODUCT)
    assert_response :unprocessable_entity
    assert_equal 'wrong_environment', json['error']

    rtdn({ packageName: PACKAGE, subscriptionNotification: { notificationType: 4, purchaseToken: 'g-test', subscriptionId: GOOGLE_PRODUCT } })
    assert_response :ok
    assert_equal 0, Spree::IapTransaction.count
  end

  test 'the environment is shown in the admin list, detail and user panel' do
    admin = create_user
    admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    txn = Iap::Recorder.new.record(@alice, 'apple', signed_payload: apple_jws(environment: 'Sandbox'))
    sign_in admin, scope: :spree_user

    get '/admin/iap_transactions'
    assert_select "#iap_transaction_#{txn.id} td", text: 'sandbox'
    get "/admin/iap_transactions/#{txn.id}"
    assert_select '#iap_transaction_details td', text: 'sandbox'
    get "/admin/users/#{@alice.id}/edit"
    assert_select '#admin_user_in_app_purchases td', text: 'sandbox'
  end

  # --- 6: restore limits -------------------------------------------------------

  test 'restore is capped at 25 items and 5 calls per minute' do
    post '/api/v1/iap/restore', params: { purchases: Array.new(26) { { platform: 'apple', signed_payload: 'x' } } }.to_json,
                                headers: bearer_for(@alice).merge('Content-Type' => 'application/json')
    assert_response :unprocessable_entity

    5.times do
      post '/api/v1/iap/restore', params: { purchases: [] }.to_json, headers: bearer_for(@alice).merge('Content-Type' => 'application/json')
      assert_response :ok
    end
    post '/api/v1/iap/restore', params: { purchases: [] }.to_json, headers: bearer_for(@alice).merge('Content-Type' => 'application/json')
    assert_response :too_many_requests
    assert_equal 'rate_limited', json['error']

    post '/api/v1/iap/restore', params: { purchases: [] }.to_json, headers: bearer_for(@bob).merge('Content-Type' => 'application/json')
    assert_response :ok
  end

  # --- 7: account tokens -------------------------------------------------------

  test 'account_token is a stable per-user UUID' do
    token = account_token_for(@alice)
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, token)
    assert_equal token, account_token_for(@alice)
    refute_equal token, account_token_for(@bob)

    get '/api/v1/iap/account_token'
    assert_response :unauthorized
  end

  test 'an Apple purchase carrying another user account token is refused with 403' do
    jws = apple_jws(appAccountToken: account_token_for(@alice).upcase)

    post_apple(@bob, jws)
    assert_response :forbidden
    assert_equal 'account_token_mismatch', json['error']
    refute pro?(@bob)

    post_apple(@alice, jws)
    assert_response :ok
    assert pro?(@alice)
  end

  test 'the account token decides ownership over first-come' do
    alice_token = account_token_for(@alice)
    post_apple(@bob, apple_jws)            # untokened first transaction of the subscription
    assert pro?(@bob)

    renewal = { transactionId: '2000000002', appAccountToken: alice_token, purchased_at: 1.minute.ago }
    post_apple_notification(apple_notification('DID_RENEW', transaction: renewal))

    assert_equal [@alice.id], Spree::IapTransaction.distinct.pluck(:user_id)
    assert pro?(@alice)
    refute pro?(@bob)
  end

  test 'a Google purchase with another user obfuscated account id is refused' do
    alice_token = account_token_for(@alice)
    stub_google_token
    stub_google_subscription('g-acct', google_subscription_json(acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
                                                                externalAccountIdentifiers: { obfuscatedExternalAccountId: alice_token }))
    post_purchase(@bob, platform: 'google', purchase_token: 'g-acct', product_id: GOOGLE_PRODUCT)
    assert_response :forbidden

    post_purchase(@alice, platform: 'google', purchase_token: 'g-acct', product_id: GOOGLE_PRODUCT)
    assert_response :ok
    assert pro?(@alice)
  end

  # --- admin authorization -----------------------------------------------------

  test 'non-admins cannot revoke' do
    txn = Iap::Recorder.new.record(@alice, 'apple', signed_payload: apple_jws)
    sign_in @bob, scope: :spree_user

    post "/admin/iap_transactions/#{txn.id}/revoke", params: { note: 'nope' }
    assert_response :redirect
    post "/admin/entitlements/#{entitlement_for(@alice).id}/revoke", params: { note: 'nope' }
    assert_response :redirect

    assert_equal 'active', txn.reload.status
    assert_equal 0, Spree::IapAuditLog.count
    assert pro?(@alice)
  end
end
