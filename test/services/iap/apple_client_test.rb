require 'test_helper'

class Iap::AppleClientTest < ActiveSupport::TestCase
  include IapTestHelpers

  PROD = 'https://api.storekit.itunes.apple.com/inApps/v1/transactions/2000000001'.freeze
  SANDBOX = 'https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/2000000001'.freeze

  setup { setup_iap_config }

  test 'is not configured without the App Store Server API key' do
    refute Iap::AppleClient.new.configured?
    assert_iap_error(:store_not_configured) { Iap::AppleClient.new.transaction_info('2000000001') }
  end

  test 'fetches transaction info with an ES256 bearer token' do
    configure_apple_api!
    signed = apple_jws
    stub = stub_request(:get, PROD).to_return(status: 200, body: { signedTransactionInfo: signed }.to_json)

    assert_equal signed, Iap::AppleClient.new.transaction_info('2000000001')

    assert_requested(:get, PROD) do |req|
      token = req.headers['Authorization'].sub('Bearer ', '')
      claims, header = JWT.decode(token, apple_api_key, true, algorithm: 'ES256', aud: 'appstoreconnect-v1', verify_aud: true)
      assert_equal 'TESTKEYID1', header['kid']
      assert_equal Iap.config.apple_issuer_id, claims['iss']
      assert_equal BUNDLE_ID, claims['bid']
      assert claims['exp'] - claims['iat'] <= 3600
      true
    end
  end

  test 'uses the sandbox host for sandbox transactions' do
    configure_apple_api!
    stub = stub_request(:get, SANDBOX).to_return(status: 200, body: { signedTransactionInfo: 'x' }.to_json)
    Iap::AppleClient.new.transaction_info('2000000001', environment: 'sandbox')
    assert_requested stub
  end

  test 'server errors and timeouts are store_unreachable' do
    configure_apple_api!
    stub_request(:get, PROD).to_return(status: 500)
    assert_iap_error(:store_unreachable) { Iap::AppleClient.new.transaction_info('2000000001') }

    WebMock.reset!
    stub_request(:get, PROD).to_timeout
    assert_iap_error(:store_unreachable) { Iap::AppleClient.new.transaction_info('2000000001') }
  end

  test 'an unknown transaction is invalid_purchase' do
    configure_apple_api!
    stub_request(:get, PROD).to_return(status: 404, body: { errorCode: 4040010 }.to_json)
    assert_iap_error(:invalid_purchase) { Iap::AppleClient.new.transaction_info('2000000001') }
  end

  test 'configuration inspect never shows the private key' do
    configure_apple_api!
    refute_includes Iap.config.inspect, 'PRIVATE KEY'
    refute_includes Iap.config.inspect, 'iap-test@'
  end
end
