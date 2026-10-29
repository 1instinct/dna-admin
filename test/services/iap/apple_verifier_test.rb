require 'test_helper'

class Iap::AppleVerifierTest < ActiveSupport::TestCase
  include IapTestHelpers

  APPLE_ROOT_G3_SHA256 = '63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179'.freeze

  setup { setup_iap_config }

  def verifier
    Iap::AppleVerifier.new
  end

  test 'verifies a StoreKit 2 JWS whose x5c chain ends at the configured root' do
    purchased = 2.days.ago.change(usec: 0)
    jws = apple_jws(purchased_at: purchased)

    v = verifier.verify(jws)

    assert_equal 'apple', v.platform
    assert_equal '2000000001', v.transaction_id
    assert_equal '1000000001', v.original_transaction_id
    assert_equal APPLE_PRODUCT, v.product_id
    assert_equal BUNDLE_ID, v.bundle_id
    assert_equal 'production', v.environment
    assert_equal 'subscription', v.kind
    assert_equal purchased, v.purchased_at
    assert_equal purchased + 30.days, v.expires_at
    assert_equal 'active', v.status
    assert_equal BigDecimal('9.99'), v.price
    assert_equal 'USD', v.currency
    assert_equal jws, v.signed_payload
    assert_equal '2000000001', v.payload['transactionId']
  end

  test 'sandbox transactions are accepted and recorded as sandbox' do
    v = verifier.verify(apple_jws(environment: 'Sandbox'))
    assert_equal 'sandbox', v.environment
  end

  test 'sandbox transactions are rejected when sandbox is disabled' do
    Iap.config.allow_sandbox = false
    assert_iap_error(:wrong_environment) { verifier.verify(apple_jws(environment: 'Sandbox')) }
  end

  test 'Xcode and local-testing environments are rejected' do
    assert_iap_error(:wrong_environment) { verifier.verify(apple_jws(environment: 'Xcode')) }
    assert_iap_error(:wrong_environment) { verifier.verify(apple_jws(environment: 'LocalTesting')) }
  end

  test 'a transaction for another bundle id is rejected' do
    assert_iap_error(:wrong_bundle) { verifier.verify(apple_jws(bundleId: 'com.other.app')) }
  end

  test 'several bundle ids can be allowed' do
    Iap.config.apple_bundle_ids = [BUNDLE_ID, 'com.example.other']
    assert_equal 'com.example.other', verifier.verify(apple_jws(bundleId: 'com.example.other')).bundle_id
  end

  test 'a chain that does not end at the configured root is rejected' do
    rogue = IapTestPki::Chain.new(root_name: 'Rogue Root CA')
    assert_iap_error(:invalid_signature) { verifier.verify(apple_jws({}, chain: rogue)) }
  end

  test 'a tampered payload is rejected' do
    header, _payload, signature = apple_jws.split('.')
    forged = Base64.urlsafe_encode64(apple_transaction_payload(productId: 'example.pro.lifetime').to_json, padding: false)
    assert_iap_error(:invalid_signature) { verifier.verify([header, forged, signature].join('.')) }
  end

  test 'a leaf certificate without the App Store marker extension is rejected' do
    leaf = iap_chain.leaf(marker: false)
    assert_iap_error(:invalid_signature) { verifier.verify(apple_jws({}, leaf: leaf)) }
  end

  test 'an expired signing certificate is rejected' do
    leaf = iap_chain.leaf(not_before: 3.days.ago, not_after: 1.day.ago)
    assert_iap_error(:invalid_signature) { verifier.verify(apple_jws({}, leaf: leaf)) }
  end

  test 'tokens without x5c or with a non-ES256 algorithm are rejected' do
    hs = JWT.encode(apple_transaction_payload, 'shared-secret', 'HS256')
    assert_iap_error(:invalid_signature) { verifier.verify(hs) }
    no_x5c = JWT.encode(apple_transaction_payload, iap_chain.leaf.last, 'ES256')
    assert_iap_error(:invalid_signature) { verifier.verify(no_x5c) }
    assert_iap_error(:invalid_signature) { verifier.verify('not-a-jws') }
  end

  test 'an expired subscription is verified with status expired' do
    v = verifier.verify(apple_jws(purchased_at: 40.days.ago))
    assert_equal 'expired', v.status
  end

  test 'a revoked transaction carries its revocation date' do
    revoked = 1.hour.ago.change(usec: 0)
    v = verifier.verify(apple_jws(revocationDate: ms(revoked), revocationReason: 0))
    assert_equal 'revoked', v.status
    assert_equal revoked, v.revoked_at
  end

  test 'an upgraded subscription transaction no longer grants access' do
    assert_equal 'expired', verifier.verify(apple_jws(isUpgraded: true)).status
  end

  test 'a non-consumable has no expiry' do
    v = verifier.verify(apple_jws(type: 'Non-Consumable', expiresDate: nil))
    assert_equal 'non_consumable', v.kind
    assert_nil v.expires_at
    assert_equal 'active', v.status
  end

  test 'notifications are verified and checked against the bundle id' do
    payload = verifier.verify_notification(apple_notification('TEST'))
    assert_equal 'TEST', payload['notificationType']

    assert_iap_error(:wrong_bundle) do
      verifier.verify_notification(apple_notification('TEST', bundle_id: 'com.other.app'))
    end
  end

  test 'production notifications must match the configured app Apple id when set' do
    Iap.config.apple_app_apple_id = '999'
    assert_iap_error(:wrong_bundle) { verifier.verify_notification(apple_notification('TEST')) }
    Iap.config.apple_app_apple_id = '1234567890'
    assert verifier.verify_notification(apple_notification('TEST'))
  end

  test 'without a configured bundle id nothing verifies' do
    Iap.config.apple_bundle_ids = []
    assert_iap_error(:store_not_configured) { verifier.verify(apple_jws) }
  end

  test 'the committed production root is Apple Root CA - G3' do
    roots = Iap::Configuration.new.apple_root_certificates
    assert_equal 1, roots.size
    assert_equal APPLE_ROOT_G3_SHA256, OpenSSL::Digest::SHA256.hexdigest(roots.first.to_der).upcase
    assert_match(/Apple Root CA - G3/, roots.first.subject.to_s)
  end
end
