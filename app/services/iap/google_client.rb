require 'openssl'
require 'erb'

module Iap
  # Google Play Developer API client (purchases.subscriptionsv2.get,
  # purchases.products.get, acknowledge). Authenticates with the service
  # account via the OAuth 2.0 JWT-bearer grant; access tokens are cached
  # in-process until shortly before they expire.
  class GoogleClient
    SCOPE = 'https://www.googleapis.com/auth/androidpublisher'.freeze
    API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'.freeze
    DEFAULT_TOKEN_URI = 'https://oauth2.googleapis.com/token'.freeze

    @token_cache = {}
    @token_mutex = Mutex.new

    class << self
      attr_reader :token_cache, :token_mutex

      def clear_token_cache!
        token_mutex.synchronize { token_cache.clear }
      end
    end

    def initialize(config = Iap.config)
      @config = config
    end

    def subscription(token)
      get("purchases/subscriptionsv2/tokens/#{enc(token)}")
    end

    def product(sku, token)
      get("purchases/products/#{enc(sku)}/tokens/#{enc(token)}")
    end

    def acknowledge(kind:, sku:, token:)
      collection = kind.to_s == 'subscription' ? 'subscriptions' : 'products'
      request(:post, "purchases/#{collection}/#{enc(sku)}/tokens/#{enc(token)}:acknowledge")
    end

    private

    def get(path)
      request(:get, path)
    end

    def request(method, path)
      raise Iap::Error.new(:store_not_configured, 'Google Play is not configured') unless @config.google_configured?

      url = "#{API}/#{enc(@config.google_package)}/#{path}"
      Iap::Http.request(method, url, headers: { 'Authorization' => "Bearer #{access_token}" }, config: @config)
    end

    def access_token
      creds = credentials
      cache_key = creds['client_email']
      cached = self.class.token_mutex.synchronize { self.class.token_cache[cache_key] }
      return cached[:token] if cached && cached[:expires_at] > Time.now + 60

      fresh = fetch_access_token(creds)
      self.class.token_mutex.synchronize { self.class.token_cache[cache_key] = fresh }
      fresh[:token]
    end

    def fetch_access_token(creds)
      token_uri = creds['token_uri'].presence || DEFAULT_TOKEN_URI
      now = Time.now.to_i
      assertion = JWT.encode({ iss: creds['client_email'], scope: SCOPE, aud: token_uri, iat: now, exp: now + 3600 },
                             OpenSSL::PKey::RSA.new(creds['private_key']), 'RS256')
      body = Iap::Http.request(:post, token_uri, form: { grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                                                         assertion: assertion }, config: @config)
      raise Iap::Error.new(:store_unreachable, 'no access token') if body['access_token'].blank?

      { token: body['access_token'], expires_at: Time.now + body['expires_in'].to_i }
    rescue Iap::Error => e
      # A rejected token exchange is our configuration problem, not a bad purchase.
      raise e if e.code == :store_unreachable

      Rails.logger.error('[iap] Google service account token exchange failed')
      raise Iap::Error.new(:store_unreachable, 'Google authentication failed')
    rescue OpenSSL::PKey::PKeyError
      raise Iap::Error.new(:store_not_configured, 'Google service account key is unreadable')
    end

    def credentials
      JSON.parse(@config.google_service_account_json)
    rescue JSON::ParserError
      raise Iap::Error.new(:store_not_configured, 'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not valid JSON')
    end

    def enc(value)
      ERB::Util.url_encode(value.to_s)
    end
  end
end
