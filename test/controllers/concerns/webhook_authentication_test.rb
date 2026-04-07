require "test_helper"

class WebhookAuthenticationTest < ActionDispatch::IntegrationTest
  test "generates valid HMAC-SHA256 hex signature" do
    secret = "test_secret_key"
    payload = '{"event_type":"case_approved"}'
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
    assert digest.length == 64
    assert digest.match?(/\A[0-9a-f]+\z/)
  end

  test "generates valid HMAC-SHA1 hex signature" do
    secret = "test_secret_key"
    payload = '{"event_type":"RX_RECEIVED"}'
    digest = OpenSSL::HMAC.hexdigest("SHA1", secret, payload)
    assert digest.length == 40
  end

  test "constant-time comparison prevents timing attacks" do
    a = "abc123"
    b = "abc123"
    c = "abc124"
    assert ActiveSupport::SecurityUtils.secure_compare(a, b)
    assert_not ActiveSupport::SecurityUtils.secure_compare(a, c)
  end
end
