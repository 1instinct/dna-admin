require 'openssl'
require 'base64'

# Generates throwaway ES256 certificate chains shaped like Apple's StoreKit
# signing chain (root CA -> intermediate CA -> leaf) so JWS verification can be
# tested without any real Apple keys.
module IapTestPki
  APPLE_LEAF_OID = '1.2.840.113635.100.6.11.1'.freeze
  APPLE_INTERMEDIATE_OID = '1.2.840.113635.100.6.2.1'.freeze

  class Chain
    attr_reader :root, :intermediate

    def self.default
      @default ||= new
    end

    def initialize(root_name: 'Test Root CA')
      @root_key = IapTestPki.ec_key
      @root = IapTestPki.build_cert(
        subject: "/CN=#{root_name}", key: @root_key, issuer: nil, issuer_key: @root_key, ca: true, serial: 1
      )
      @intermediate_key = IapTestPki.ec_key
      @intermediate = IapTestPki.build_cert(
        subject: "/CN=#{root_name} Intermediate", key: @intermediate_key, issuer: @root,
        issuer_key: @root_key, ca: true, serial: 2, marker_oid: APPLE_INTERMEDIATE_OID
      )
      @leaves = {}
    end

    # A signing certificate issued by this chain's intermediate.
    def leaf(marker: true, not_before: Time.now - 3600, not_after: Time.now + 86_400)
      key = [marker, not_before.to_i / 60, not_after.to_i / 60]
      @leaves[key] ||= begin
        leaf_key = IapTestPki.ec_key
        cert = IapTestPki.build_cert(
          subject: '/CN=Test StoreKit Signing', key: leaf_key, issuer: @intermediate,
          issuer_key: @intermediate_key, ca: false, serial: 3 + @leaves.size,
          marker_oid: (marker ? APPLE_LEAF_OID : nil), not_before: not_before, not_after: not_after
        )
        [cert, leaf_key]
      end
    end

    def sign(payload, leaf: self.leaf, headers: {})
      cert, key = leaf
      x5c = [cert, @intermediate, @root].map { |c| Base64.strict_encode64(c.to_der) }
      JWT.encode(payload, key, 'ES256', { x5c: x5c }.merge(headers))
    end
  end

  module_function

  def ec_key
    OpenSSL::PKey::EC.generate('prime256v1')
  end

  def build_cert(subject:, key:, issuer:, issuer_key:, ca:, serial:, marker_oid: nil,
                 not_before: Time.now - 86_400, not_after: Time.now + (365 * 86_400))
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = serial
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.issuer = issuer ? issuer.subject : cert.subject
    cert.public_key = key
    cert.not_before = not_before
    cert.not_after = not_after

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = issuer || cert
    if ca
      cert.add_extension(ef.create_extension('basicConstraints', 'CA:TRUE', true))
      cert.add_extension(ef.create_extension('keyUsage', 'keyCertSign,cRLSign', true))
    else
      cert.add_extension(ef.create_extension('basicConstraints', 'CA:FALSE', true))
      cert.add_extension(ef.create_extension('keyUsage', 'digitalSignature', true))
    end
    cert.add_extension(ef.create_extension('subjectKeyIdentifier', 'hash', false))
    cert.add_extension(OpenSSL::X509::Extension.new(marker_oid, OpenSSL::ASN1::Null.new(nil).to_der)) if marker_oid

    cert.sign(issuer_key, OpenSSL::Digest.new('SHA256'))
    cert
  end
end
