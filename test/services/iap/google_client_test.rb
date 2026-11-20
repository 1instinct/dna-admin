require 'test_helper'

class Iap::GoogleClientTest < ActiveSupport::TestCase
  include IapTestHelpers

  setup { setup_iap_config }

  test 'gets an access token with a service-account JWT assertion and caches it' do
    token_stub = stub_google_token
    stub_google_subscription('tok-1', google_subscription_json)

    client = Iap::GoogleClient.new
    client.subscription('tok-1')
    client.subscription('tok-1')

    assert_requested token_stub, times: 1
    assert_requested(:post, GOOGLE_TOKEN_URL) do |req|
      form = Rack::Utils.parse_query(req.body)
      assert_equal 'urn:ietf:params:oauth:grant-type:jwt-bearer', form['grant_type']
      claims, = JWT.decode(form['assertion'], google_rsa_key.public_key, true, algorithm: 'RS256')
      assert_equal 'https://www.googleapis.com/auth/androidpublisher', claims['scope']
      assert_equal GOOGLE_TOKEN_URL, claims['aud']
      true
    end
    assert_requested(:get, "#{GOOGLE_API}/purchases/subscriptionsv2/tokens/tok-1",
                     headers: { 'Authorization' => 'Bearer test-access-token' }, times: 2)
  end

  test 'product purchases and acknowledgements use the products endpoints' do
    stub_google_token
    stub_google_product(GOOGLE_PRODUCT, 'tok-2', { purchaseState: 0 })
    ack = stub_google_acknowledge('products', GOOGLE_PRODUCT, 'tok-2')
    sub_ack = stub_google_acknowledge('subscriptions', GOOGLE_PRODUCT, 'tok-3')

    client = Iap::GoogleClient.new
    assert_equal 0, client.product(GOOGLE_PRODUCT, 'tok-2')['purchaseState']
    client.acknowledge(kind: 'non_consumable', sku: GOOGLE_PRODUCT, token: 'tok-2')
    client.acknowledge(kind: 'subscription', sku: GOOGLE_PRODUCT, token: 'tok-3')

    assert_requested ack
    assert_requested sub_ack
  end

  test 'Play outages are store_unreachable, bad tokens are invalid_purchase' do
    stub_google_token
    stub_google_subscription('down', {}, status: 503)
    stub_google_subscription('gone', {}, status: 410)
    stub_google_subscription('bad', {}, status: 400)

    client = Iap::GoogleClient.new
    assert_iap_error(:store_unreachable) { client.subscription('down') }
    assert_iap_error(:invalid_purchase) { client.subscription('gone') }
    assert_iap_error(:invalid_purchase) { client.subscription('bad') }
  end

  test 'a failing token exchange is store_unreachable, not invalid_purchase' do
    stub_request(:post, GOOGLE_TOKEN_URL).to_return(status: 400, body: { error: 'invalid_grant' }.to_json)
    assert_iap_error(:store_unreachable) { Iap::GoogleClient.new.subscription('tok') }
  end

  test 'is not configured without package and service account' do
    Iap.config.google_service_account_json = nil
    assert_iap_error(:store_not_configured) { Iap::GoogleClient.new.subscription('tok') }
  end
end
