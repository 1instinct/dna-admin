module WebhookAuthentication
  extend ActiveSupport::Concern

  private

  def verify_hmac!(secret_env_key, header_name)
    secret = ENV[secret_env_key]
    if secret.blank?
      return if Rails.env.development? || Rails.env.test?
      head :unauthorized and return
    end

    signature = request.headers[header_name]
    if signature.blank?
      head :unauthorized and return
    end

    payload = request.body.read
    request.body.rewind

    valid = try_hmac(:SHA256, payload, signature, secret) ||
            try_hmac(:SHA1, payload, signature, secret)

    head :unauthorized and return unless valid
  end

  def try_hmac(algorithm, payload, signature, secret)
    digest = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new(algorithm.to_s), secret, payload
    )
    return true if ActiveSupport::SecurityUtils.secure_compare(digest, signature.to_s)

    base64_digest = Base64.strict_encode64([digest].pack("H*"))
    ActiveSupport::SecurityUtils.secure_compare(base64_digest, signature.to_s)
  end
end
