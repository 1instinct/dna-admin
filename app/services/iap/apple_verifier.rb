require 'openssl'
require 'base64'

module Iap
  # Verifies StoreKit 2 signed data (JWS, ES256, x5c header): the certificate
  # chain must lead to a configured root (Apple Root CA - G3 in production), the
  # leaf and intermediate must carry Apple's App Store marker extensions, and
  # the signature must verify with the leaf key. Then bundle id and environment
  # are checked.
  class AppleVerifier
    LEAF_MARKER_OID = '1.2.840.113635.100.6.11.1'.freeze
    INTERMEDIATE_MARKER_OID = '1.2.840.113635.100.6.2.1'.freeze

    KINDS = {
      'Auto-Renewable Subscription' => 'subscription',
      'Non-Renewing Subscription' => 'subscription',
      'Non-Consumable' => 'non_consumable',
      'Consumable' => 'consumable'
    }.freeze

    def initialize(config = Iap.config)
      @config = config
    end

    # Signed transaction (JWSTransaction) -> VerifiedTransaction.
    def verify(jws)
      payload = decode(jws)
      check_app!(payload['bundleId'], payload['environment'])
      build(payload, jws)
    end

    # Signed notification (responseBodyV2 signedPayload) -> decoded payload.
    # Nested signedTransactionInfo / signedRenewalInfo are verified separately.
    def verify_notification(signed_payload)
      payload = decode(signed_payload)
      app = payload['data'].presence || payload['summary'].presence || {}
      check_app!(app['bundleId'], app['environment'])
      if @config.apple_app_apple_id.present? && app['environment'] == 'Production' &&
         app['appAppleId'].to_s != @config.apple_app_apple_id.to_s
        raise Iap::Error.new(:wrong_bundle, 'notification is for another app')
      end
      payload
    end

    # Verifies signature and chain only; returns the payload hash.
    def decode(jws)
      raise Iap::Error.new(:invalid_signature) unless jws.is_a?(String) && jws.count('.') == 2

      header = JWT.decode(jws, nil, false).last
      raise Iap::Error.new(:invalid_signature, 'unexpected algorithm') unless header['alg'] == 'ES256'

      certs = Array(header['x5c']).map { |der| OpenSSL::X509::Certificate.new(Base64.strict_decode64(der)) }
      raise Iap::Error.new(:invalid_signature, 'missing certificate chain') if certs.size < 2

      leaf = verified_leaf(certs[0], certs[1])
      JWT.decode(jws, leaf.public_key, true, algorithm: 'ES256').first
    rescue JWT::DecodeError, OpenSSL::X509::CertificateError, OpenSSL::PKey::PKeyError, ArgumentError
      raise Iap::Error.new(:invalid_signature)
    end

    private

    def verified_leaf(leaf, intermediate)
      roots = @config.apple_root_certificates
      raise Iap::Error.new(:store_not_configured, 'no Apple root certificate configured') if roots.blank?

      store = OpenSSL::X509::Store.new
      roots.each { |root| store.add_cert(root) }
      # Only the leaf and intermediate come from the token; the anchor must be ours.
      context = OpenSSL::X509::StoreContext.new(store, leaf, [intermediate])
      raise Iap::Error.new(:invalid_signature, 'untrusted certificate chain') unless context.verify

      chain = context.chain
      unless chain.size == 3 && marker?(chain[0], LEAF_MARKER_OID) && marker?(chain[1], INTERMEDIATE_MARKER_OID)
        raise Iap::Error.new(:invalid_signature, 'not an App Store signing chain')
      end

      leaf
    end

    def marker?(cert, oid)
      cert.extensions.any? { |ext| ext.oid == oid }
    end

    def check_app!(bundle_id, environment)
      raise Iap::Error.new(:store_not_configured, 'APPLE_BUNDLE_ID is not set') if @config.apple_bundle_ids.blank?
      raise Iap::Error.new(:wrong_bundle) unless @config.apple_bundle_ids.include?(bundle_id)

      env = environment.to_s.downcase
      return if env == 'production'
      return if env == 'sandbox' && @config.allow_sandbox

      raise Iap::Error.new(:wrong_environment)
    end

    def build(p, jws)
      purchased_at = ms_time(p['purchaseDate'])
      expires_at = ms_time(p['expiresDate'])
      revoked_at = ms_time(p['revocationDate'])
      status =
        if revoked_at then 'revoked'
        elsif p['isUpgraded'] then 'expired'
        elsif expires_at && expires_at <= Time.current then 'expired'
        else 'active'
        end

      VerifiedTransaction.new(
        platform: 'apple',
        transaction_id: p['transactionId'].to_s,
        original_transaction_id: (p['originalTransactionId'] || p['transactionId']).to_s,
        product_id: p['productId'],
        bundle_id: p['bundleId'],
        kind: KINDS[p['type']],
        environment: p['environment'].to_s.downcase,
        status: status,
        purchased_at: purchased_at,
        expires_at: expires_at,
        revoked_at: revoked_at,
        revocation_reason: p['revocationReason']&.to_s,
        price: p['price'] ? BigDecimal(p['price'].to_s) / 1000 : nil,
        currency: p['currency'],
        order_id: p['webOrderLineItemId']&.to_s,
        acknowledged: true,
        signed_payload: jws,
        payload: p
      )
    end

    def ms_time(value)
      value.present? ? Time.zone.at(value.to_i / 1000.0) : nil
    end
  end
end
