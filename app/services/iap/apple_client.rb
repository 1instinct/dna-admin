require 'openssl'
require 'erb'

module Iap
  # App Store Server API client (authoritative transaction state). Auth is a
  # short-lived ES256 JWT signed with the App Store Connect in-app purchase key.
  class AppleClient
    HOSTS = {
      'production' => 'https://api.storekit.itunes.apple.com',
      'sandbox' => 'https://api.storekit-sandbox.itunes.apple.com'
    }.freeze

    def initialize(config = Iap.config)
      @config = config
    end

    def configured?
      @config.apple_api_configured?
    end

    # Returns the signedTransactionInfo JWS for the transaction id.
    def transaction_info(transaction_id, environment: 'production')
      raise Iap::Error.new(:store_not_configured, 'App Store Server API key is not configured') unless configured?

      host = HOSTS.fetch(environment.to_s, HOSTS['production'])
      body = Iap::Http.request(:get, "#{host}/inApps/v1/transactions/#{ERB::Util.url_encode(transaction_id)}",
                               headers: { 'Authorization' => "Bearer #{bearer_token}" }, config: @config)
      body['signedTransactionInfo'].presence || raise(Iap::Error.new(:invalid_purchase, 'no transaction info'))
    end

    private

    def bearer_token
      key = OpenSSL::PKey::EC.new(@config.apple_private_key)
      now = Time.now.to_i
      claims = { iss: @config.apple_issuer_id, iat: now, exp: now + 300, aud: 'appstoreconnect-v1',
                 bid: @config.apple_bundle_ids.first }
      JWT.encode(claims, key, 'ES256', { kid: @config.apple_key_id, typ: 'JWT' })
    rescue OpenSSL::PKey::PKeyError
      raise Iap::Error.new(:store_not_configured, 'App Store Server API key is unreadable')
    end
  end
end
