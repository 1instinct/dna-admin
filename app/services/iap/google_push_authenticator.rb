module Iap
  # Authenticates Pub/Sub push requests carrying Play RTDN messages.
  #
  # Required: the OIDC token Pub/Sub sends as "Authorization: Bearer <JWT>",
  # verified against Google's signing keys (RS256), issuer accounts.google.com,
  # audience GOOGLE_PLAY_RTDN_AUDIENCE and the verified email
  # GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT.
  # Opt-in fallback: GOOGLE_PLAY_RTDN_TOKEN compared with the X-Iap-Push-Token
  # header (headers, unlike query strings, are not in router logs).
  # With neither configured every request is refused.
  class GooglePushAuthenticator
    CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs'.freeze
    ISSUERS = ['https://accounts.google.com', 'accounts.google.com'].freeze
    TOKEN_HEADER = 'X-Iap-Push-Token'.freeze
    JWKS_TTL = 3600

    @jwks_cache = nil
    @jwks_mutex = Mutex.new

    class << self
      attr_reader :jwks_mutex
      attr_accessor :jwks_cache

      def clear_cache!
        jwks_mutex.synchronize { self.jwks_cache = nil }
      end
    end

    def initialize(config = Iap.config)
      @config = config
    end

    def authenticate!(request)
      bearer = request.authorization.to_s
      if bearer.start_with?('Bearer ') && @config.google_push_oidc_configured?
        return verify_oidc!(bearer.split(' ', 2).last.to_s.strip)
      end

      shared = request.headers[TOKEN_HEADER].to_s
      if @config.google_rtdn_token.present? && shared.present? &&
         ActiveSupport::SecurityUtils.secure_compare(shared, @config.google_rtdn_token)
        return true
      end

      raise Iap::Error.new(:unauthorized, 'push request is not authenticated')
    end

    private

    def verify_oidc!(token)
      claims, = JWT.decode(token, nil, true,
                           algorithms: ['RS256'], jwks: jwks_loader,
                           iss: ISSUERS, verify_iss: true,
                           aud: @config.google_rtdn_audience, verify_aud: true,
                           verify_expiration: true)
      verified_email = claims['email_verified'] == true || claims['email_verified'].to_s == 'true'
      unless verified_email && claims['email'] == @config.google_rtdn_service_account
        raise Iap::Error.new(:unauthorized, 'push token from an unexpected service account')
      end

      true
    rescue JWT::DecodeError, JWT::JWKError
      raise Iap::Error.new(:unauthorized, 'invalid push token')
    end

    # Cached Google JWKS; refetched when expired or when a token names an
    # unknown key id (Google rotates keys).
    def jwks_loader
      lambda do |options|
        cached = self.class.jwks_cache
        # Unknown kid refetches at most every 5 minutes (no fetch per forged token).
        stale_for_kid = options[:kid_not_found] && cached && cached[:fetched_at] < Time.now - 300
        if cached.nil? || cached[:expires_at] < Time.now || stale_for_kid
          keys = Iap::Http.request(:get, CERTS_URL, config: @config)
          cached = { keys: keys, fetched_at: Time.now, expires_at: Time.now + JWKS_TTL }
          self.class.jwks_mutex.synchronize { self.class.jwks_cache = cached }
        end
        cached[:keys].deep_symbolize_keys
      end
    end
  end
end
