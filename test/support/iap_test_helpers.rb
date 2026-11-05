require 'securerandom'

# Shared helpers for the in-app purchase tests. Every identifier here is a
# placeholder; no real bundle ids, product ids or credentials.
module IapTestHelpers
  BUNDLE_ID = 'com.example.app'.freeze
  PACKAGE = 'com.example.app'.freeze
  APPLE_PRODUCT = 'example.pro.monthly'.freeze
  GOOGLE_PRODUCT = 'example_pro_monthly'.freeze
  GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
  PUSH_AUDIENCE = 'https://admin.example.com/api/v1/iap/google/notifications'.freeze
  PUSH_SERVICE_ACCOUNT = 'pubsub-push@example-project.iam.gserviceaccount.com'.freeze
  GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs'.freeze
  GOOGLE_API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{PACKAGE}".freeze

  def self.included(base)
    base.teardown do
      Iap.reset_config!
      Iap::GoogleClient.clear_token_cache!
      Iap::GooglePushAuthenticator.clear_cache!
      Iap::RateLimiter.store = nil
    end
  end

  def iap_chain
    IapTestPki::Chain.default
  end

  def setup_iap_config(**overrides)
    config = Iap::Configuration.new
    config.apple_bundle_ids = [BUNDLE_ID]
    config.apple_root_certificates = [iap_chain.root]
    config.allow_sandbox = true
    config.google_package = PACKAGE
    config.google_service_account_json = google_service_account_json
    config.google_rtdn_audience = PUSH_AUDIENCE
    config.google_rtdn_service_account = PUSH_SERVICE_ACCOUNT
    overrides.each { |k, v| config.public_send("#{k}=", v) }
    Iap.config = config
  end

  def configure_apple_api!
    Iap.config.apple_key_id = 'TESTKEYID1'
    Iap.config.apple_issuer_id = '00000000-0000-0000-0000-000000000000'
    Iap.config.apple_private_key = apple_api_key.to_pem
  end

  def apple_api_key
    @@apple_api_key ||= OpenSSL::PKey::EC.generate('prime256v1')
  end

  def google_rsa_key
    @@google_rsa_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def google_service_account_json
    {
      type: 'service_account',
      client_email: 'iap-test@example-project.iam.gserviceaccount.com',
      private_key: google_rsa_key.to_pem,
      token_uri: GOOGLE_TOKEN_URL
    }.to_json
  end

  def push_signing_key
    @@push_signing_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  # Stubs Google's JWKS endpoint with our generated push-signing key.
  def stub_google_certs
    jwk = JWT::JWK.new(push_signing_key, kid: 'test-push-kid')
    stub_request(:get, GOOGLE_CERTS_URL)
      .to_return(status: 200, body: { keys: [jwk.export] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # An OIDC token as Pub/Sub push sends it.
  # push_token(claim_overrides) or push_token({}, key: other_rsa_key)
  def push_token(overrides = {}, opts = {})
    key = opts[:key] || push_signing_key
    now = Time.now.to_i
    claims = { iss: 'https://accounts.google.com', aud: PUSH_AUDIENCE, email: PUSH_SERVICE_ACCOUNT,
               email_verified: true, sub: '1234567890', iat: now, exp: now + 3600 }.merge(overrides)
    JWT.encode(claims, key, 'RS256', { kid: 'test-push-kid' })
  end

  def ms(time)
    (time.to_f * 1000).to_i
  end

  def create_user(email = nil)
    email ||= "user-#{SecureRandom.hex(4)}@example.com"
    Spree.user_class.create!(email: email, password: 'secret123', password_confirmation: 'secret123')
  end

  def iap_product(platform: 'apple', product_id: APPLE_PRODUCT, kind: 'subscription', entitlement: 'pro')
    Spree::IapProduct.find_or_create_by!(platform: platform, product_id: product_id) do |p|
      p.kind = kind
      p.entitlement = entitlement
      p.name = product_id
    end
  end

  def apple_transaction_payload(overrides = {})
    purchased = overrides.delete(:purchased_at) || 1.day.ago
    {
      transactionId: '2000000001',
      originalTransactionId: '1000000001',
      webOrderLineItemId: '3000000001',
      bundleId: BUNDLE_ID,
      productId: APPLE_PRODUCT,
      purchaseDate: ms(purchased),
      originalPurchaseDate: ms(purchased),
      expiresDate: ms(purchased + 30.days),
      quantity: 1,
      type: 'Auto-Renewable Subscription',
      inAppOwnershipType: 'PURCHASED',
      signedDate: ms(Time.current),
      environment: 'Production',
      transactionReason: 'PURCHASE',
      storefront: 'USA',
      price: 9990,
      currency: 'USD'
    }.merge(overrides)
  end

  # apple_jws(payload_overrides) or apple_jws({}, chain: other_chain, leaf: cert_and_key)
  def apple_jws(overrides = {}, opts = {})
    chain = opts[:chain] || iap_chain
    payload = apple_transaction_payload(overrides.dup)
    opts[:leaf] ? chain.sign(payload, leaf: opts[:leaf]) : chain.sign(payload)
  end

  def apple_notification(type, subtype: nil, transaction: {}, renewal: nil, uuid: SecureRandom.uuid,
                         bundle_id: BUNDLE_ID, environment: 'Production', chain: iap_chain, signed_at: Time.current)
    data = {
      appAppleId: 1234567890,
      bundleId: bundle_id,
      bundleVersion: '1',
      environment: environment,
      signedTransactionInfo: apple_jws(transaction, { chain: chain })
    }
    data[:signedRenewalInfo] = chain.sign(renewal) if renewal
    payload = {
      notificationType: type,
      notificationUUID: uuid,
      data: data,
      version: '2.0',
      signedDate: ms(signed_at)
    }
    payload[:subtype] = subtype if subtype
    chain.sign(payload)
  end

  def google_subscription_json(overrides = {})
    {
      kind: 'androidpublisher#subscriptionPurchaseV2',
      startTime: 1.day.ago.utc.iso8601,
      regionCode: 'US',
      subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      latestOrderId: 'GPA.0000-0000-0000-00001',
      acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
      lineItems: [
        {
          productId: GOOGLE_PRODUCT,
          expiryTime: 29.days.from_now.utc.iso8601,
          autoRenewingPlan: { autoRenewEnabled: true }
        }
      ]
    }.merge(overrides)
  end

  def stub_google_token
    stub_request(:post, GOOGLE_TOKEN_URL)
      .to_return(status: 200, body: { access_token: 'test-access-token', expires_in: 3600 }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_google_subscription(token, json, status: 200)
    stub_request(:get, "#{GOOGLE_API}/purchases/subscriptionsv2/tokens/#{token}")
      .to_return(status: status, body: json.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_google_product(sku, token, json, status: 200)
    stub_request(:get, "#{GOOGLE_API}/purchases/products/#{sku}/tokens/#{token}")
      .to_return(status: status, body: json.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_google_acknowledge(kind_path, sku, token)
    stub_request(:post, "#{GOOGLE_API}/purchases/#{kind_path}/#{sku}/tokens/#{token}:acknowledge")
      .to_return(status: 204, body: '')
  end

  def assert_iap_error(code)
    error = assert_raises(Iap::Error) { yield }
    assert_equal code, error.code, "expected #{code}, got #{error.code}: #{error.message}"
    error
  end

  def entitlement_for(user, key = 'pro')
    Spree::Entitlement.find_by(user_id: user.id, key: key)
  end

  def pro?(user)
    Spree::Entitlement.current_for(user, 'pro').present?
  end

  def bearer_for(user)
    token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: 3600)
    { 'Authorization' => "Bearer #{token.respond_to?(:plaintext_token) && token.plaintext_token || token.token}" }
  end
end
