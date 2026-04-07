require "test_helper"
require "webmock/minitest"

class HoneybeeClientTest < ActiveSupport::TestCase
  setup do
    REDIS.flushdb
    ENV["HONEYBEE_API_BASE"] = "https://partners.honeybeehealth.com"
    ENV["HONEYBEE_AUTH_BASE"] = "https://auth.honeybeehealth.com"
    ENV["HONEYBEE_CLIENT_ID"] = "test_hb_client"
    ENV["HONEYBEE_SECRET_KEY"] = "test_hb_secret"
    @client = HoneybeeClient.new

    stub_request(:post, "https://auth.honeybeehealth.com/oauth/token")
      .to_return(
        status: 200,
        body: { access_token: "test_token_123", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "fetch_order returns order data" do
    stub_request(:get, "https://partners.honeybeehealth.com/v1/orders/HB-001")
      .with(headers: { "Authorization" => "Bearer test_token_123" })
      .to_return(
        status: 200,
        body: { id: "HB-001", status: "processing" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @client.fetch_order("HB-001")
    assert_equal "processing", result["status"]
  end

  test "caches OAuth token in Redis" do
    stub_request(:get, "https://partners.honeybeehealth.com/v1/orders/HB-002")
      .to_return(status: 200, body: "{}",  headers: { "Content-Type" => "application/json" })

    @client.fetch_order("HB-002")
    @client.fetch_order("HB-002")

    assert_requested(:post, "https://auth.honeybeehealth.com/oauth/token", times: 1)
  end

  test "refreshes expired token" do
    stub_request(:post, "https://auth.honeybeehealth.com/oauth/token")
      .to_return(
        status: 200,
        body: { access_token: "token_1", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      ).then.to_return(
        status: 200,
        body: { access_token: "token_2", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://partners.honeybeehealth.com/v1/orders/HB-003")
      .to_return(status: 200, body: "{}",  headers: { "Content-Type" => "application/json" })

    @client.fetch_order("HB-003")
    REDIS.del("honeybee:oauth_token")
    @client.fetch_order("HB-003")

    assert_requested(:post, "https://auth.honeybeehealth.com/oauth/token", times: 2)
  end
end
