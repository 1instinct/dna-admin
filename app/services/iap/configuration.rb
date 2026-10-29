require 'openssl'

module Iap
  # IAP settings, read from ENV. Secrets (App Store Server API key, Play service
  # account) are never logged: #inspect only says whether they are present.
  #
  #   APPLE_BUNDLE_ID                   bundle id(s), comma-separated
  #   APPLE_APP_APPLE_ID                numeric App Store app id (optional; checked on production notifications)
  #   APPLE_IAP_KEY_ID                  App Store Server API key id
  #   APPLE_IAP_ISSUER_ID               App Store Server API issuer id
  #   APPLE_IAP_PRIVATE_KEY             App Store Server API .p8 contents (PEM; literal \n allowed)
  #   IAP_ALLOW_SANDBOX                 "false" rejects sandbox/TestFlight purchases (default: allowed)
  #   GOOGLE_PLAY_PACKAGE               Android package name
  #   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  service account key JSON (contents)
  #   GOOGLE_PLAY_RTDN_TOKEN            shared token expected as ?token= on the Pub/Sub push URL (optional)
  class Configuration
    APPLE_ROOT_GLOB = 'config/certs/AppleRootCA-*.cer'.freeze

    attr_accessor :apple_bundle_ids, :apple_app_apple_id, :apple_key_id, :apple_issuer_id,
                  :apple_private_key, :allow_sandbox, :google_package, :google_service_account_json,
                  :google_rtdn_token, :open_timeout, :read_timeout
    attr_writer :apple_root_certificates

    def self.from_env(env = ENV)
      new.tap do |c|
        c.apple_bundle_ids = env['APPLE_BUNDLE_ID'].to_s.split(',').map(&:strip).reject(&:empty?)
        c.apple_app_apple_id = env['APPLE_APP_APPLE_ID'].presence
        c.apple_key_id = env['APPLE_IAP_KEY_ID'].presence
        c.apple_issuer_id = env['APPLE_IAP_ISSUER_ID'].presence
        c.apple_private_key = env['APPLE_IAP_PRIVATE_KEY'].presence&.gsub('\n', "\n")
        c.allow_sandbox = env.fetch('IAP_ALLOW_SANDBOX', 'true').to_s.downcase != 'false'
        c.google_package = env['GOOGLE_PLAY_PACKAGE'].presence
        c.google_service_account_json = env['GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'].presence
        c.google_rtdn_token = env['GOOGLE_PLAY_RTDN_TOKEN'].presence
      end
    end

    def initialize
      @apple_bundle_ids = []
      @allow_sandbox = true
      @open_timeout = 5
      @read_timeout = 10
    end

    # Trust anchors for StoreKit JWS chains: Apple Root CA - G3 (DER files in
    # config/certs). Tests inject their own generated root.
    def apple_root_certificates
      @apple_root_certificates ||= Dir[Rails.root.join(APPLE_ROOT_GLOB)].sort.map do |path|
        OpenSSL::X509::Certificate.new(File.binread(path))
      end
    end

    def apple_api_configured?
      [apple_key_id, apple_issuer_id, apple_private_key].all?(&:present?) && apple_bundle_ids.any?
    end

    def google_configured?
      google_package.present? && google_service_account_json.present?
    end

    def inspect
      "#<Iap::Configuration apple_bundle_ids=#{apple_bundle_ids.inspect} " \
        "apple_api=#{apple_api_configured? ? 'configured' : 'missing'} allow_sandbox=#{allow_sandbox} " \
        "google_package=#{google_package.inspect} google_api=#{google_configured? ? 'configured' : 'missing'}>"
    end
    alias to_s inspect
  end
end
