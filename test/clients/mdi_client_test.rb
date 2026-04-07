require "test_helper"
require "webmock/minitest"

class MdiClientTest < ActiveSupport::TestCase
  setup do
    ENV["MDI_API_BASE"] = "https://api.mdintegrations.com/v1"
    ENV["MDI_CLIENT_ID"] = "test_client_id"
    ENV["MDI_CLIENT_SECRET"] = "test_client_secret"
    @client = MdiClient.new
  end

  test "fetch_encounter returns encounter data on success" do
    stub_request(:get, "https://api.mdintegrations.com/v1/encounters/enc_123")
      .with(headers: {
        "Authorization" => "Basic #{Base64.strict_encode64('test_client_id:test_client_secret')}"
      })
      .to_return(
        status: 200,
        body: { id: "enc_123", status: "PASS" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @client.fetch_encounter("enc_123")
    assert_equal "PASS", result["status"]
  end

  test "fetch_encounter raises on 404" do
    stub_request(:get, "https://api.mdintegrations.com/v1/encounters/enc_999")
      .to_return(status: 404, body: { error: "Not found" }.to_json)

    assert_raises(Faraday::ResourceNotFound) do
      @client.fetch_encounter("enc_999")
    end
  end

  test "fetch_encounter retries on 500" do
    stub_request(:get, "https://api.mdintegrations.com/v1/encounters/enc_retry")
      .to_return(status: 500, body: "Internal Server Error")
      .then.to_return(
        status: 200,
        body: { id: "enc_retry", status: "PENDING" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @client.fetch_encounter("enc_retry")
    assert_equal "PENDING", result["status"]
  end
end
